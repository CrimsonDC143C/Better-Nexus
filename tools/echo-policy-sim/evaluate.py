#!/usr/bin/env python3
"""Select on training seeds, then evaluate frozen candidates on held-out seeds.

Standard library only. Calls actual Lua candidate/production decisions. All
mechanics and workloads remain synthetic; no game, network or SavedVariables.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
import math
import pathlib
import shutil
import statistics
import subprocess
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
METRICS = ('complete', 'missing', 'select', 'banish', 'reroll', 'freeze', 'draws', 'actions')


def bucket():
    return dict.fromkeys(('n',) + METRICS, 0)


class Results:
    def __init__(self):
        self.total = defaultdict(bucket)
        self.profiles = defaultdict(lambda: defaultdict(bucket))
        self.cells = defaultdict(lambda: defaultdict(bucket))
        self.seeds = defaultdict(lambda: defaultdict(bucket))

    def add(self, row):
        values = {name: int(row[name]) for name in METRICS}
        assert values['complete'] in (0, 1)
        assert values['actions'] == sum(values[n] for n in ('select', 'banish', 'reroll', 'freeze'))
        assert row['stop'] in ('COMPLETE', 'PICKS_EXHAUSTED')
        assert (row['stop'] == 'COMPLETE') == (values['complete'] == 1)
        assert (values['missing'] == 0) == (values['complete'] == 1)
        p, policy, seed = row['profile'], row['policy'], int(row['seed'])
        for target in (self.total[policy], self.profiles[p][policy],
                       self.cells[(p, row['scenario'])][policy], self.seeds[(p, seed)][policy]):
            target['n'] += 1
            for name, value in values.items():
                target[name] += value


def read_results(path, policies, first, count):
    results = Results()
    seen = set()
    with path.open(newline='', encoding='utf-8') as handle:
        for row in csv.DictReader(handle):
            key = (row['profile'], row['scenario'], int(row['seed']), row['policy'])
            assert key not in seen, f'duplicate trial {key}'
            assert first <= key[2] < first + count and key[3] in policies, f'foreign trial {key}'
            seen.add(key)
            results.add(row)
    assert len(results.cells) == 72, 'the fixed corpus must contain all 72 cells'
    for cell in results.cells.values():
        assert set(cell) == set(policies), 'missing policy'
        assert all(row['n'] == count for row in cell.values()), 'missing trial'
    return results


def rate(row, name):
    return row[name] / row['n']


def rank(scores):
    # User-confirmed order: completion, missing copies, then search actions.
    # Resource counts stay separate in the report; no invented currency value.
    return sorted(scores, key=lambda p: (-rate(scores[p], 'complete'), rate(scores[p], 'missing'),
                                        rate(scores[p], 'actions') - rate(scores[p], 'select'), p))


def select(training):
    primary = rank(training.total)[0]
    by_profile = {name: rank(scores)[0] for name, scores in training.profiles.items()}
    # Secondary, predeclared minimax-regret candidate. It is selected before
    # looking at evaluation data, not a fallback chosen after a bad result.
    best = {name: rate(scores[by_profile[name]], 'complete') for name, scores in training.profiles.items()}
    regret = {p: max(best[name] - rate(scores[p], 'complete')
                     for name, scores in training.profiles.items()) for p in training.total}
    robust = min(training.total, key=lambda p: (regret[p], rank(training.total).index(p)))
    return {'primary': primary, 'minimax_regret': robust, 'by_profile': by_profile,
            'training_worst_profile_regret': regret}


def paired_interval(results, policy, metric='complete', profile=None):
    # Cluster by seed across the fixed scenarios/profiles. This does not count
    # correlated cases that share a seed as independent samples.
    blocks = defaultdict(lambda: [0, 0, 0])
    for (name, seed), policies in results.seeds.items():
        if profile is not None and name != profile:
            continue
        current, control = policies[policy], policies['released']
        assert current['n'] == control['n']
        b = blocks[seed]
        b[0] += current[metric]; b[1] += control[metric]; b[2] += current['n']
    samples = [(a - b) / n for a, b, n in blocks.values()]
    mean = statistics.mean(samples)
    margin = 1.96 * statistics.stdev(samples) / math.sqrt(len(samples)) if len(samples) >= 30 else None
    return {'mean': mean, 'low': None if margin is None else mean - margin,
            'high': None if margin is None else mean + margin, 'seed_blocks': len(samples),
            'method': 'paired seed-cluster normal 95% interval; fixed synthetic corpus'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_trials(lua, path, first, count, policies):
    with path.open('w', newline='', encoding='utf-8') as handle:
        subprocess.run(lua + ['tools/echo-policy-sim/trials.lua', str(first), str(count), ','.join(policies)],
                       cwd=ROOT, stdout=handle, check=True)
    return read_results(path, policies, first, count)


def interval_text(interval):
    if interval['low'] is None:
        return f"{100*interval['mean']:+.2f} pp; too few seeds for interval"
    return f"{100*interval['mean']:+.2f} pp [{100*interval['low']:+.2f}, {100*interval['high']:+.2f}]"


def report(selection, training, evaluation, registry, config):
    primary = selection['primary']
    delta = paired_interval(evaluation, primary)
    proven = delta['low'] is not None and delta['low'] > 0
    lines = ['# Better-Nexus rolling-policy experiment', '',
             '**Scope: simulator research only. Orbweaver addon development is abandoned.**', '',
             f"Training-selected candidate: **{primary}**. Held-out completion change versus released: **{interval_text(delta)}**.", '',
             ('The held-out result supports this candidate on this fixed synthetic corpus.' if proven else
              'The held-out result does not establish a completion improvement. Do not promote it as a proven upgrade.'), '',
             'This is the best training candidate among the declared policies, not a proof of a globally optimal strategy.',
             'It is not native server evidence. No live addon setting or release was changed.', '',
             '## Objective and protocol', '',
             '- Rank complete Wishlists first, then fewer missing copies, then fewer search actions.',
             '- Weight each of the 72 fixed workload/mechanics cells equally.',
             '- Select every candidate using training only. Freeze selection before evaluation starts.',
             '- Evaluate the released control, fixed Banish-first control, training winner, minimax-regret candidate, and profile winners.',
             '- Use paired seed-cluster 95% intervals. These measure seed sampling on this fixed corpus, not uncertainty about server mechanics.',
             '- Report each resource separately. No DPS score, resource currency conversion, or unseen-draw access.',
             f"- Training seeds: 1..{config['train']}; evaluation: {config['test_start']}..{config['test_start']+config['test']-1}.", '',
             '## Frozen candidate rules', '', '```json', json.dumps(registry[primary], indent=2), '```', '',
             'For implementation, use the candidate function in `candidates.lua` as the executable reference.',
             '`pair` freezes one of two still-needed offers before selecting the other; it does not freeze a lone target to spend Banishes searching around it.',
             '`reserve=N` postpones search while picks remaining exceed N times the missing copies. `family_safe` protects all Wishlist quality siblings.',
             '`abundant` uses Banish first only when remaining Banishes exceed Rerolls times unfrozen slots. `one_banish` permits at most one Banish before an available Reroll.', '',
             '## Held-out totals', '',
             '| Policy | Runs | Complete | Missing/run | Picks/run | Banish/run | Reroll/run | Freeze/run | Paired completion vs released |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |']
    # Stable policy order, not a held-out ranking or post-hoc selection.
    for policy in sorted(evaluation.total):
        row = evaluation.total[policy]
        lines.append(f"| {policy} | {row['n']} | {100*rate(row,'complete'):.2f}% | " +
                     ' | '.join(f'{rate(row,m):.3f}' for m in ('missing','select','banish','reroll','freeze')) +
                     f" | {interval_text(paired_interval(evaluation,policy))} |")
    lines += ['', '## Mechanics sensitivity', '',
              '| Profile | Training winner | Frozen primary completion change | Profile winner completion change |',
              '| --- | --- | --- | --- |']
    for profile, winner in sorted(selection['by_profile'].items()):
        lines.append(f'| {profile} | {winner} | {interval_text(paired_interval(evaluation,primary,profile=profile))} | '
                     f'{interval_text(paired_interval(evaluation,winner,profile=profile))} |')
    lines += ['', f"Minimax-regret candidate selected on training: **{selection['minimax_regret']}**.", '',
              '## Worst held-out cells for the frozen primary', '',
              '| Profile / workload | Completion change | Missing-copy change/run |', '| --- | ---: | ---: |']
    cells = []
    for key, scores in evaluation.cells.items():
        a,b = scores[primary],scores['released']
        cells.append((rate(a,'complete')-rate(b,'complete'), key, rate(a,'missing')-rate(b,'missing')))
    for change, key, missing in sorted(cells)[:8]:
        lines.append(f'| {key[0]} / {key[1]} | {100*change:+.2f} pp | {missing:+.3f} |')
    lines += ['', '## Limits and next use', '',
              'All profiles use hypothetical weights. `none`, `spell`, and `family` vary run-long Banish exclusion scope.',
              '`replacement` allows repeated IDs and has no stack cap. `unique-capped` disallows duplicate IDs on one board and stops drawing an ID after five owned copies.',
              'These are six alternative mechanics models, not six confirmed server modes. Freezes persist until selected; charges do not regenerate.',
              'The corpus covers short and long runs, exact copies, rare targets, quality siblings, asymmetric budgets, Freeze-only runs, partial builds and impossible completion.',
              'Native odds, pool eligibility, caps, regeneration, combat and confirmation failures remain outside this policy research model.',
              'To decide a live policy, supply evidence-backed profile/pool fixtures and rerun this same protocol. Do not treat the unknown rules as a reason to rebuild the simulator.', '',
              '## Training ranking (not evaluation ranking)', '',
              '| Policy | Complete | Missing/run | Search actions/run |', '| --- | ---: | ---: | ---: |']
    for policy in rank(training.total):
        row=training.total[policy]
        lines.append(f"| {policy} | {100*rate(row,'complete'):.2f}% | {rate(row,'missing'):.3f} | {rate(row,'actions')-rate(row,'select'):.3f} |")
    return '\n'.join(lines)+'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua', nargs='+', default=[shutil.which('luajit') or 'luajit'], help='Lua command, e.g. --lua python .tools/lua_jit.py')
    parser.add_argument('--train',type=int,default=200)
    parser.add_argument('--test',type=int,default=1000)
    parser.add_argument('--test-start',type=int,default=100001)
    parser.add_argument('--output',type=pathlib.Path,default=ROOT/'build/policy-lab')
    args=parser.parse_args()
    if not 1<=args.train<=10000 or not 1<=args.test<=10000 or args.test_start<=args.train:
        parser.error('counts must be 1..10000; test-start must be beyond training seeds')
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    raw=subprocess.check_output(args.lua+['tools/echo-policy-sim/trials.lua','--list'],cwd=ROOT,text=True)
    registry={row['id']:row for row in csv.DictReader(io.StringIO(raw))}
    subprocess.run(args.lua+['tests/prototype/search_order_sim.lua'],cwd=ROOT,check=True)
    subprocess.run(args.lua+['tests/prototype/policy_lab.lua'],cwd=ROOT,check=True)
    config={'schema':'nexus-policy-evaluation/v2','train':args.train,'test':args.test,'test_start':args.test_start,
            'lua':args.lua,'objective':'completion, missing copies, search actions','corpus':'rolling-corpus/v2'}
    source_paths=sorted((ROOT/'tools/echo-policy-sim').glob('*.lua'))+[pathlib.Path(__file__),
        ROOT/'logic/EchoWeaver.lua',ROOT/'tests/prototype/policy_adapter.lua']
    sources={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in source_paths}
    print('TRAINING',len(registry),'policies;',args.train,'seeds per cell',flush=True)
    training=run_trials(args.lua,output/'training.csv',1,args.train,list(registry))
    selection=select(training)
    # Persist the selection BEFORE any held-out trial is run.
    selection_path=output/'selection.json'
    selection_path.write_text(json.dumps({'config':config,'selection':selection,'policies':registry,'sources':sources},indent=2)+'\n')
    evaluated=sorted(set(['released','banish-first',selection['primary'],selection['minimax_regret']]+list(selection['by_profile'].values())))
    print('FROZEN SELECTION',selection['primary'],'EVALUATING',','.join(evaluated),flush=True)
    evaluation=run_trials(args.lua,output/'evaluation.csv',args.test_start,args.test,evaluated)
    text=report(selection,training,evaluation,registry,config)
    (output/'report.md').write_text(text,encoding='utf-8')
    result={'config':config,'selection':selection,'heldout_totals':dict(evaluation.total),
            'primary_completion_delta':paired_interval(evaluation,selection['primary']),
            'primary_missing_delta':paired_interval(evaluation,selection['primary'],'missing'),
            'artifacts':{name:sha(output/name) for name in ('training.csv','evaluation.csv','selection.json','report.md')},'sources':sources}
    (output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    assert all(sha(ROOT/name)==digest for name,digest in sources.items()),'source changed during experiment'
    print('REPORT',output/'report.md',flush=True)
    print('PRIMARY',selection['primary'],interval_text(result['primary_completion_delta']),flush=True)
    return 0


if __name__=='__main__':
    raise SystemExit(main())
