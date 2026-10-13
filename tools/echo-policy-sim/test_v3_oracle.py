"""Run exact oracle decisions through the existing Lua simulator, with new seeds."""
import argparse
from dataclasses import replace
from pathlib import Path
from optimal import Solver
from optimal_v3 import cases
from lua_bridge import LuaPolicies


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lupa-path',type=Path)
    parser.add_argument('--count',type=int,default=3000)
    args=parser.parse_args()
    assert args.count>=1000
    bridge=LuaPolicies(args.lupa_path)
    execute=bridge.lua.eval('''function(s,callback)
        local Sim=dofile('tools/echo-policy-sim/simulator.lua')
        return Sim.Run(P,s,{id='exact-v3-oracle',decide=function(_,input,view) return callback(input,view) end}).complete
    end''')
    for name,m,initial in cases():
        solver=Solver(m)
        expected=float(solver.solve(initial)[0])
        by_id={echo:i for i,echo in enumerate(m.ids)}
        def decide(observation,view):
            board=[]
            for j in range(1,4):
                card=observation['cards'][j]
                board.append((by_id[card['spellId']],bool(card['isFrozen'] or card['isCarried'] or card['justFrozen']),bool(card['isGuaranteed'])))
            charges=observation['charges']
            s=m.state(board,int(observation['horizon']),int(charges['banish']),int(charges['reroll']),int(charges['freeze']),
                      [int(observation['owned']['bySpell'][echo] or 0) for echo in m.ids])
            available={view['pool'][j]['spellId'] for j in range(1,len(view['pool'])+1)}
            banned=sum(1<<i for i,echo in enumerate(m.ids) if echo not in available)
            penalized=sum(1<<i for i,echo in enumerate(m.ids)
                          if view['penalizedFamilies'][observation['catalog']['familyOf'][echo]])
            s=replace(s,banned=banned,penalized=penalized,since_reroll=int(view['banishesSinceReroll']))
            solver.solve(s)
            kind,index=solver.decisions[s]
            return bridge.table(dict(type='take' if kind=='select' else kind,
                index=index+1 if index>=0 else None,spellId=m.ids[s.board[index][0]] if index>=0 else None))
        families={}
        for i,echo in enumerate(m.ids):
            family=families.setdefault(str(m.families[i]),{})
            family[len(family)]=echo
        scenario=dict(picks=initial.picks,resources=dict(banish=initial.banish,reroll=initial.reroll,freeze=initial.freeze),
            allowFreeze=True, families=families,targets=[dict(spellId=m.ids[i],stacks=t) for i,t in enumerate(m.targets) if t],
            pool=[dict(spellId=echo,weight=m.weights[i]) for i,echo in enumerate(m.ids)],
            board=[dict(spellId=m.ids[c[0]]) for c in initial.board],
            profile=dict(version=3,banishExclusion=m.exclusion,rerollExcludeCurrent=m.exclude_current,
                         selectFamilyBoost=float(m.boost),rerollFamilyPenalty=float(m.penalty),rerollPenaltyLifetime=m.lifetime))
        wins=0
        for seed in range(600001,600001+args.count):
            scenario['seed']=seed
            wins+=bool(execute(bridge.table(scenario),decide))
        observed=wins/args.count
        assert abs(observed-expected)<0.025,(name,observed,expected)
        print(f'PASS {name}: exact {expected:.6f}; Lua {wins}/{args.count}={observed:.6f}; no environment seed enters oracle')


if __name__=='__main__':
    main()
