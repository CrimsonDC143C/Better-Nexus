"""Exact reference for declared family-weight and next-board exclusion hypotheses.

This is a small-model oracle, not a server formula. Every modifier is explicit.
The parent solver's rational arithmetic and fail-closed state limit still apply.
"""
from dataclasses import dataclass, replace
from fractions import Fraction as F
import argparse
import json
from pathlib import Path
from optimal import Model, State, Solver, InvalidModel


@dataclass(frozen=True)
class WeightedState(State):
    penalized: int = 0
    avoid: int = 0  # Only during a draw batch; cleared before the next decision.


class WeightedModel(Model):
    def __init__(self, *args, boost, penalty, lifetime, exclude_current, **kwargs):
        super().__init__(*args, **kwargs)
        self.boost, self.penalty = F(str(boost)), F(str(penalty))
        self.lifetime, self.exclude_current = lifetime, exclude_current
        if self.boost < 1 or not 0 < self.penalty <= 1 or lifetime not in ('board','run') or type(exclude_current) is not bool:
            raise InvalidModel('invalid explicit family-weight hypothesis')

    def state(self, *args, **kwargs):
        return WeightedState(**super().state(*args, **kwargs).__dict__)

    def prepare(self, s, action):
        post, slots = super().prepare(s, action)
        if action[0]=='reroll':
            families={self.families[c[0]] for c in s.board}
            penalty=s.penalized
            for i,family in enumerate(self.families):
                if family in families:
                    penalty |= 1 << i
            avoid=sum(1 << i for i in {c[0] for c in s.board}) if self.exclude_current else 0
            post=replace(post, penalized=penalty, avoid=avoid)
        return post,slots

    def eligible(self, s, board):
        return tuple(i for i in super().eligible(s,board) if not s.avoid & (1 << i))

    def weight(self, s, i):
        weight=F(self.weights[i])
        if any(n>0 and self.families[j]==self.families[i] for j,n in enumerate(s.owned)):
            weight *= self.boost
        if s.penalized & (1 << i):
            weight *= self.penalty
        return weight

    def settle(self, s):
        return replace(s, avoid=0, penalized=s.penalized if self.lifetime=='run' else 0)

    def outcomes(self, s, action):
        post,slots=self.prepare(s,action)
        def draw(at,board,probability):
            if at==len(slots):
                yield probability,self.settle(replace(post,board=tuple(board)))
                return
            choices=[(i,self.weight(post,i)) for i in self.eligible(post,board)]
            total=sum(w for _,w in choices)
            if not total:
                raise InvalidModel('synthetic pool exhausted; no v3 certificate')
            for i,w in choices:
                updated=list(board);updated[slots[at]]=(i,False,False)
                yield from draw(at+1,updated,probability*w/total)
        yield from draw(0,post.board,F(1))

    def sample(self, s, action, rng):
        # Keep this API exact: sample the rational cumulative distribution.
        outcomes=list(self.outcomes(s,action))
        denominator=1
        from math import lcm
        for probability,_ in outcomes:
            denominator=lcm(denominator,probability.denominator)
        threshold=rng.randrange(denominator)
        for probability,child in outcomes:
            threshold-=int(probability*denominator)
            if threshold<0:
                return child
        raise AssertionError('probability mass is not one')

    def describe(self):
        return dict(super().describe(),version='finite-normal-board/v3',select_family_boost=str(self.boost),
                    reroll_family_penalty=str(self.penalty),penalty_lifetime=self.lifetime,exclude_current=self.exclude_current)


def cases():
    for exclusion in ('spell','family'):
        for lifetime in ('board','run'):
            m=WeightedModel([1]*6,[1,0,0,0,0,0],families=[0,1,2,3,1,4],exclusion=exclusion,
                            boost=2,penalty='1/2',lifetime=lifetime,exclude_current=True)
            yield exclusion+'-'+lifetime,m,m.state([1,2,3],1,banish=1,reroll=1)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('build/optimal-v3.json'))
    parser.add_argument('--scenario',type=Path,help='JSON model/state input, with all four weight-modifier assumptions explicit')
    parser.add_argument('--limit',type=int,default=200000)
    args=parser.parse_args()
    if args.scenario:
        data=json.loads(args.scenario.read_text(encoding='utf-8'))
        m=WeightedModel(**data['model'])
        certificate=Solver(m,args.limit).certificate(m.state(**data['state']))
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(certificate,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({k:certificate[k] for k in ('status','value','action','states')}))
        return
    results=[]
    for name,m,s in cases():
        certificate=Solver(m,args.limit).certificate(s)
        results.append(dict(name=name,certificate=certificate))
        print(name,certificate['action'],certificate['value'])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
