"""Predeclared early-Banish challenge. Never tune from the held-out outcome."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import time
from plan_study import aggregate, paired, BASE


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lua',nargs='+',default=['luajit'])
    p.add_argument('--output',type=Path,default=Path('build/early-study'))
    p.add_argument('--train',type=int,default=20)
    p.add_argument('--test',type=int,default=200)
    args=p.parse_args()
    assert 1<=args.train<=1000 and 2<=args.test<=1000
    args.output.mkdir(parents=True,exist_ok=True)
    sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in Path('tools/echo-policy-sim').glob('*')
             if f.suffix in ('.lua','.py')}
    policies=['early-banish','adaptive-0-settle',BASE]
    def run(corpus,first,count,phase):
        output=args.output/f'{corpus}-{phase}.csv'
        started=time.perf_counter()
        with output.open('w',encoding='utf-8',newline='') as stream:
            subprocess.run([*args.lua,'tools/echo-policy-sim/early_trials.lua',str(first),str(count),corpus],stdout=stream,check=True)
        rows=list(csv.DictReader(output.open(encoding='utf-8')))
        cells={(r['profile'],r['scenario']) for r in rows}
        assert len(cells)==(72 if corpus=='v2' else 864)
        keys={(r['profile'],r['scenario'],int(r['seed']),r['policy']) for r in rows}
        assert len(keys)==len(rows)
        assert keys=={(profile,scenario,seed,policy) for profile,scenario in cells
                      for seed in range(first,first+count) for policy in policies}
        for r in rows:
            assert r['stop'] in ('COMPLETE','PICKS_EXHAUSTED')
            assert int(r['complete'])==int(int(r['missing'])==0)
            assert int(r['actions'])==sum(int(r[k]) for k in ('select','banish','reroll','freeze'))
        return rows,time.perf_counter()-started
    training={}
    for corpus in ('v2','v3'):
        rows,elapsed=run(corpus,700001,args.train,'training')
        training[corpus]=dict(aggregate={c:aggregate(rows,c) for c in policies},seconds=elapsed)
    # Selection is recorded before any final rows are generated. The experiment
    # still reports a rejected challenger; that is not permission to deploy it.
    chosen='early-banish' if all(training[v]['aggregate']['early-banish']['complete']>
        training[v]['aggregate']['adaptive-0-settle']['complete'] for v in training) else 'adaptive-0-settle'
    receipt=dict(selected=chosen,training=training,train_start=700001,train_count=args.train,
                 test_start=800001,test_count=args.test,sources=sources)
    (args.output/'selection.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print('Frozen early-Banish choice:',chosen,flush=True)
    result=dict(selection=receipt,evaluation={})
    for corpus in ('v2','v3'):
        rows,elapsed=run(corpus,800001,args.test,'evaluation')
        result['evaluation'][corpus]=dict(aggregate={c:aggregate(rows,c) for c in policies},seconds=elapsed,
            early_vs_adaptive=paired(rows,'early-banish','adaptive-0-settle'),early_vs_incumbent=paired(rows,'early-banish',BASE),
            profiles={profile:paired([r for r in rows if r['profile']==profile],'early-banish','adaptive-0-settle')
                      for profile in sorted({r['profile'] for r in rows})})
        print(corpus,json.dumps({k:result['evaluation'][corpus][k] for k in ('aggregate','early_vs_adaptive','seconds')}),flush=True)
    assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in sources.items()),'source changed'
    result['artifacts']={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in args.output.glob('*.csv')}
    (args.output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
