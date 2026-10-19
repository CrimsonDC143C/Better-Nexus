"""Client-informed direction, hypothetical magnitudes: frozen train/test sensitivity."""
import argparse
import hashlib
import json
from pathlib import Path
from plan_study import trials, aggregate, paired, BASE


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lua',nargs='+',default=['luajit'])
    p.add_argument('--output',type=Path,default=Path('build/mechanics-study'))
    p.add_argument('--train',type=int,default=50)
    p.add_argument('--test',type=int,default=200)
    p.add_argument('--train-start',type=int,default=400001)
    p.add_argument('--test-start',type=int,default=500001)
    args=p.parse_args()
    assert 1<=args.train<=10000 and 2<=args.test<=10000
    assert args.train_start>331000 and args.test_start>args.train_start+args.train
    args.output.mkdir(parents=True,exist_ok=True)
    candidates=[BASE,'adaptive-0-hold','adaptive-0-settle','banish-reserve4-pair','reroll-pair']
    sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest()
             for f in sorted(Path('tools/echo-policy-sim').glob('*')) if f.suffix in ('.lua','.py')}
    rows,seconds=trials(args.lua,args.train_start,args.train,candidates,args.output/'training.csv',864,'client-v3')
    training={c:aggregate(rows,c) for c in candidates}
    def rank(c):
        a=training[c]
        return (-a['complete'],a['missing'],sum(a[k] for k in ('banish','reroll','freeze')),c)
    selected=min(candidates,key=rank)
    selection=dict(selected=selected,training=training,train_start=args.train_start,train_count=args.train,
                   test_start=args.test_start,test_count=args.test,seconds=seconds,sources=sources,
                   assumptions='72 fixed mechanics profiles x 12 workloads; equal weight, not a server distribution')
    (args.output/'selection.json').write_text(json.dumps(selection,indent=2)+'\n',encoding='utf-8')
    print('Frozen sensitivity selection:',selected,training,flush=True)
    policies=list(dict.fromkeys([selected,BASE,'released']))
    rows,seconds=trials(args.lua,args.test_start,args.test,policies,args.output/'evaluation.csv',864,'client-v3')
    assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in sources.items()), 'source changed'
    profiles=sorted({r['profile'] for r in rows})
    by_profile={profile:[r for r in rows if r['profile']==profile] for profile in profiles}
    result=dict(selection=selection,evaluation={c:aggregate(rows,c) for c in policies},seconds=seconds,
        versus_incumbent=paired(rows,selected,BASE),versus_released=paired(rows,selected,'released'),
        profiles={profile:dict(aggregate={c:aggregate(subset,c) for c in policies},
                    versus_incumbent=paired(subset,selected,BASE)) for profile,subset in by_profile.items()},
        artifacts={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in args.output.glob('*.csv')},
        status='MODEL_CONDITIONAL_ONLY; no server-optimality certificate')
    (args.output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ('evaluation','versus_incumbent','versus_released','seconds')},indent=2))


if __name__=='__main__':
    main()
