"""Exact complete-policy regressions for the counterexample-derived challenger."""
import argparse
from pathlib import Path
from optimal import Model, Solver, benchmarks
from lua_bridge import LuaPolicies


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--lupa-path',type=Path)
    args=p.parse_args()
    bridge=LuaPolicies(args.lupa_path)
    bridge.lua.execute('''local get=C.Get
        C.Get=function(id)
            if id=='early-banish' then return dofile('tools/echo-policy-sim/early_banish.lua').Build(get('adaptive-0-settle')) end
            return get(id)
        end''')
    for exclusion in ('spell','family'):
        m=Model([1,2,3,2],[1,1,0,0],exclusion=exclusion)
        s=m.state([0,1,2],2,banish=1)
        exact=Solver(m).solve(s)
        early=Solver(m,policy=bridge.bind(m,'early-banish')).solve(s)
        adaptive=Solver(m,policy=bridge.bind(m,'adaptive-0-settle')).solve(s)
        assert early==exact, (exclusion,early,exact)
        assert early[0]>adaptive[0]
        print(exclusion,'closed exact completion gap',str(early[0]-adaptive[0]))
    for name,m,s in benchmarks():
        early=Solver(m,policy=bridge.bind(m,'early-banish')).solve(s)
        optimum=Solver(m).solve(s)
        assert early==optimum,(name,early,optimum)
    print('PASS: seven exact complete-policy cases, including needed-offer early Banish')


if __name__=='__main__':
    main()
