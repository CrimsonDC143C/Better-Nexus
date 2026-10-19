"""Differential full-run tests: independent Python model versus existing Lua executor."""
import argparse
import random
from optimal import Model, Solver, benchmarks
from lua_bridge import LuaPolicies


def check(bridge):
    execute = bridge.lua.eval('''function(s, actions)
        local Sim=dofile('tools/echo-policy-sim/simulator.lua')
        local at=0
        return Sim.Run(P,s,{id='differential-test',decide=function(_,input)
            at=at+1
            local a=actions[at]
            assert(a,'unexpected extra decision')
            for i,c in ipairs(input.cards) do
                assert(c.spellId==a.board[i][1], 'board ID mismatch')
                assert(not not (c.isFrozen or c.isCarried or c.justFrozen)==a.board[i][2], 'held mismatch')
            end
            assert(input.horizon==a.picks, 'pick mismatch')
            return {type=a.kind=='select' and 'take' or a.kind,index=a.index,spellId=a.spellId}
        end})
    end''')
    runs = 0
    for exclusion in ("none", "spell", "family"):
        for unique in (False, True):
            for seed in range(1, 31):
                rng = random.Random(seed)
                m = Model([1, 2, 3, 4, 5, 6], [1, 1, 0, 0, 0, 0], exclusion=exclusion, unique=unique, cap=4)
                s = initial = m.state([0, 2, 3], 3, 1, 1, 1)
                draws, actions, counts = {}, [], dict(select=0, banish=0, reroll=0, freeze=0)
                while not m.terminal(s):
                    action = rng.choice(m.actions(s))
                    kind, index = action
                    counts[kind] += 1
                    actions.append(dict(kind=kind,index=index + 1 if index >= 0 else None,
                        spellId=m.ids[s.board[index][0]] if index >= 0 else None,picks=s.picks,
                        board=[(m.ids[c[0]], c[1]) for c in s.board]))
                    _, slots = m.prepare(s, action)
                    s = m.sample(s, action, rng)
                    if slots:
                        draws.setdefault(kind, {})[counts[kind]] = {i + 1: m.ids[s.board[i][0]] for i in slots}
                scenario = dict(seed=seed, picks=initial.picks, resources=dict(banish=1,reroll=1,freeze=1),allowFreeze=True,
                    families={str(i): {0: echo} for i, echo in enumerate(m.ids)},
                    targets=[dict(spellId=m.ids[i],stacks=t) for i,t in enumerate(m.targets) if t],
                    pool=[dict(spellId=echo,weight=m.weights[i]) for i,echo in enumerate(m.ids)],
                    board=[dict(spellId=m.ids[c[0]]) for c in initial.board], draws=draws,
                    profile=dict(version=2,banishExclusion=exclusion,uniqueOffers=unique,maxStacks=4))
                result = execute(bridge.table(scenario), bridge.table(actions))
                assert result['missing'] == m.missing(s)
                assert result['complete'] == (m.missing(s) == 0)
                for kind, count in counts.items():
                    assert result[kind] == count
                for i, echo in enumerate(m.ids):
                    assert (result['owned'][echo] or 0) == s.owned[i]
                runs += 1
    for name, m, s in benchmarks():
        optimum = Solver(m).solve(s)
        for policy in ('released', 'banish-family-safe-pair'):
            actual = Solver(m, policy=bridge.bind(m, policy)).solve(s)
            assert optimum >= actual, (name, policy)
    print(f'PASS: {runs} full differential trajectories and 10 exact real-policy bounds')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--lupa-path')
    args = parser.parse_args()
    from pathlib import Path
    check(LuaPolicies(Path(args.lupa_path) if args.lupa_path else None))
