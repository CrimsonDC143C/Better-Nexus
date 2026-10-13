"""Catalog-backed, model-conditional study. Local source facts are not draw odds."""
import argparse
import hashlib
import json
from pathlib import Path
from plan_study import trials, aggregate, paired, BASE


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lua',nargs='+',default=['luajit'])
    p.add_argument('--catalog',type=Path,required=True)
    p.add_argument('--output',type=Path,default=Path('build/catalog-study'))
    p.add_argument('--train',type=int,default=20)
    p.add_argument('--test',type=int,default=200)
    p.add_argument('--train-start',type=int,default=900001)
    p.add_argument('--test-start',type=int,default=1000001)
    args=p.parse_args()
    assert 1<=args.train<=10000 and 2<=args.test<=10000
    assert args.train_start>810000 and args.test_start>args.train_start+args.train
    assert args.test_start+args.test<2147483647
    assert args.catalog.resolve().is_relative_to(Path('build').resolve()),'private generated catalog must remain in build/'
    args.output.mkdir(parents=True,exist_ok=True)
    candidates=[BASE,'adaptive-0-settle','reroll-pair','released']
    files=[f for f in Path('tools/echo-policy-sim').glob('*') if f.suffix in ('.lua','.py')]
    files.extend(Path(f) for f in ('tests/prototype/policy_adapter.lua','Nexus.toc',
        'core/EchoCatalogSource.lua','data/DefaultProfile.lua','logic/Model.lua','logic/Strategy.lua',
        'logic/Ratchet.lua','logic/EchoWeaver.lua','logic/OrbPolicy.lua','logic/Policy.lua'))
    files.append(args.catalog)
    sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(files)}
    def run(first,count,policies,path):
        return trials(args.lua,first,count,policies,path,144,str(args.catalog),'tools/echo-policy-sim/catalog_trials.lua')
    rows,seconds=run(args.train_start,args.train,candidates,args.output/'training.csv')
    training={c:aggregate(rows,c) for c in candidates}
    def rank(c):
        v=training[c]
        return (-v['complete'],v['missing'],sum(v[k] for k in ('banish','reroll','freeze')),c)
    selected=min(candidates,key=rank)
    selection=dict(selected=selected,training=training,train_start=args.train_start,train_count=args.train,
        test_start=args.test_start,test_count=args.test,seconds=seconds,sources=sources,
        assumptions='12 explicit profiles x 12 synthetic character/Wishlist workloads; uniform eligible-ID base weights, not observed odds')
    (args.output/'selection.json').write_text(json.dumps(selection,indent=2)+'\n',encoding='utf-8')
    print('Frozen catalog selection:',selected,flush=True)
    # Always evaluate all four controls: avoids hiding model-dependent order reversals.
    rows,seconds=run(args.test_start,args.test,candidates,args.output/'evaluation.csv')
    assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in sources.items()),'source changed during study'
    profiles={profile:[r for r in rows if r['profile']==profile] for profile in sorted({r['profile'] for r in rows})}
    def comparison(reference):
        value=paired(rows,selected,reference)
        if args.test<30:
            value['ci95']=None
            value['inference']='SMOKE_ONLY; insufficient seed clusters for an improvement claim'
        return value
    result=dict(selection=selection,evaluation={c:aggregate(rows,c) for c in candidates},seconds=seconds,
        versus_incumbent=comparison(BASE),versus_released=comparison('released'),
        profiles={profile:{c:aggregate(subset,c) for c in candidates} for profile,subset in profiles.items()},
        artifacts={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in args.output.glob('*.csv')},
        status='MODEL_CONDITIONAL_ONLY; current catalog facts do not establish the live draw formula')
    (args.output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ('evaluation','versus_incumbent','versus_released','seconds')},indent=2))


if __name__=='__main__': main()
