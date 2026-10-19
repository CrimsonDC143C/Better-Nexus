"""Fresh-seed rollout-policy study. Freeze training selection before evaluation."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import time

BASE = 'banish-family-safe-pair'


def trials(command, first, count, policies, output, cells=72, corpus=None,
           runner='tools/echo-policy-sim/trials.lua'):
    start = time.perf_counter()
    with output.open('w', encoding='utf-8', newline='') as stream:
        subprocess.run([*command, runner, str(first), str(count), ','.join(policies), *([corpus] if corpus else [])],
                       stdout=stream, check=True)
    rows = list(csv.DictReader(output.open(encoding='utf-8')))
    assert len(rows) == cells * count * len(policies), 'incomplete study'
    keys = {(r['profile'],r['scenario'],int(r['seed']),r['policy']) for r in rows}
    assert len(keys) == len(rows), 'duplicate trials'
    assert {int(r['seed']) for r in rows} == set(range(first,first+count))
    assert {r['policy'] for r in rows} == set(policies)
    assert all(r['stop'] in ('COMPLETE','PICKS_EXHAUSTED') for r in rows)
    cell_keys={(r['profile'],r['scenario']) for r in rows}
    assert len(cell_keys)==cells, 'wrong mechanics/workload coverage'
    assert keys=={(profile,scenario,seed,policy) for profile,scenario in cell_keys
                  for seed in range(first,first+count) for policy in policies}, 'unbalanced cells'
    for r in rows:
        assert int(r['complete'])==int(int(r['missing'])==0), 'wrong completion settlement'
        assert int(r['actions'])==sum(int(r[k]) for k in ('select','banish','reroll','freeze')), 'wrong action accounting'
    return rows, time.perf_counter() - start


def aggregate(rows, policy):
    subset = [r for r in rows if r['policy'] == policy]
    n = len(subset)
    result = dict(runs=n, complete=sum(int(r['complete']) for r in subset))
    for field in ('missing', 'banish', 'reroll', 'freeze', 'actions'):
        result[field] = sum(int(r[field]) for r in subset) / n
    result['completion_rate'] = result['complete'] / n
    return result


def paired(rows, candidate, reference):
    keyed = {(r['profile'], r['scenario'], r['seed'], r['policy']): r for r in rows}
    clusters, wins, losses = {}, [], []
    for r in rows:
        if r['policy'] != candidate:
            continue
        other = keyed[(r['profile'],r['scenario'],r['seed'],reference)]
        delta = int(r['complete']) - int(other['complete'])
        clusters.setdefault(r['seed'], []).append(delta)
        if delta:
            (wins if delta > 0 else losses).append({k:r[k] for k in ('profile','scenario','seed')})
    values = [statistics.mean(v) for v in clusters.values()]
    mean = statistics.mean(values)
    margin = 1.96 * statistics.stdev(values) / math.sqrt(len(values)) if len(values)>1 else None
    return dict(delta=mean, ci95=[mean-margin,mean+margin] if margin is not None else None,
                wins=len(wins), losses=len(losses), loss_examples=losses[:12], seed_clusters=len(values))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lua', nargs='+', default=['luajit'])
    p.add_argument('--output', type=Path, default=Path('build/planning-study'))
    p.add_argument('--train', type=int, default=10)
    p.add_argument('--test', type=int, default=200)
    p.add_argument('--train-start', type=int, default=200001)
    p.add_argument('--test-start', type=int, default=300001)
    p.add_argument('--candidates', default='plan-16,plan-64')
    args = p.parse_args()
    assert 1 <= args.train <= 10000 and 2 <= args.test <= 10000
    assert args.train_start > 101000 and args.test_start > args.train_start + args.train
    args.output.mkdir(parents=True, exist_ok=True)
    candidates = list(dict.fromkeys([BASE, *args.candidates.split(',')]))
    sources = {str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(Path('tools/echo-policy-sim').glob('*.lua'))}
    rows, train_seconds = trials(args.lua,args.train_start,args.train,candidates,args.output/'training.csv')
    training = {c:aggregate(rows,c) for c in candidates}
    def rank(c):
        v=training[c]
        return (-v['complete'],v['missing'],v['banish']+v['reroll']+v['freeze'],c)
    selected = min(candidates,key=rank)
    receipt = dict(selected=selected, training=training, train_start=args.train_start,train_count=args.train,
                   test_start=args.test_start,test_count=args.test,sources=sources,train_seconds=train_seconds)
    (args.output/'selection.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print('Frozen selection:',selected,training,flush=True)
    evaluation = list(dict.fromkeys([selected,BASE,'released']))
    rows, test_seconds = trials(args.lua,args.test_start,args.test,evaluation,args.output/'evaluation.csv')
    assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in sources.items()), 'source changed during study'
    result = dict(selection=receipt, evaluation={c:aggregate(rows,c) for c in evaluation},test_seconds=test_seconds,
        versus_incumbent=paired(rows,selected,BASE),versus_released=paired(rows,selected,'released'),
        profiles={profile:{c:aggregate([r for r in rows if r['profile']==profile],c) for c in evaluation}
                  for profile in sorted({r['profile'] for r in rows})},
        artifacts={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in args.output.glob('*.csv')},
        optimality='Sampled or adaptive policy is NOT a proven global optimum; optimal.py is not used as a shortcut here.')
    (args.output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ('evaluation','versus_incumbent','versus_released','test_seconds')},indent=2))


if __name__ == '__main__':
    main()
