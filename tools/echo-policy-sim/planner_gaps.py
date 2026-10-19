"""Measure exact whole-policy regret, including downstream decisions, in small models."""
import argparse
import json
from pathlib import Path
from optimal import Model, Solver, benchmarks
from lua_bridge import LuaPolicies


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lupa-path',type=Path)
    p.add_argument('--output',type=Path,default=Path('build/planner-gaps.json'))
    p.add_argument('--policies',default='released,banish-family-safe-pair,adaptive-0-settle,plan-16')
    args=p.parse_args()
    bridge=LuaPolicies(args.lupa_path)
    cases=benchmarks()
    for exclusion in ('none','spell','family'):
        for board in ([0,1,2],[2,2,3]):
            m=Model([1,2,3,2],[1,1,0,0],exclusion=exclusion)
            cases.append((f'two-targets-{exclusion}-{board}',m,m.state(board,2,banish=1)))
    report=[]
    for name,m,s in cases:
        solver=Solver(m)
        optimum=solver.solve(s)
        record=dict(name=name,optimal=solver.certificate(s),policies={})
        for policy in args.policies.split(','):
            fixed=Solver(m,policy=bridge.bind(m,policy))
            value=fixed.solve(s)
            assert value<=optimum
            record['policies'][policy]=dict(value=[str(v) for v in value],
                completion_gap=str(optimum[0]-value[0]),optimal=value==optimum,
                action=fixed.decisions[s])
        report.append(record)
        print(name,{k:v['completion_gap'] for k,v in record['policies'].items()},flush=True)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
