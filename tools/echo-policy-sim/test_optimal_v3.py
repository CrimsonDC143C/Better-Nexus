import unittest
from dataclasses import replace
from fractions import Fraction as F
from optimal import Solver
from optimal_v3 import WeightedModel


class WeightedTests(unittest.TestCase):
    def model(self,**kwargs):
        options=dict(boost=2,penalty='1/4',lifetime='board',exclude_current=True)
        options.update(kwargs)
        return WeightedModel([1]*6,[0,0,0,0,0,2],families=[0,1,2,0,3,4],**options)

    def test_analytic_penalty(self):
        m=self.model(boost=1)
        s=m.state([0,1,2],2,reroll=1)
        outcomes=list(m.outcomes(s,('reroll',-1)))
        self.assertEqual(sum(p for p,_ in outcomes),1)
        self.assertEqual(sum(p for p,c in outcomes if c.board[0][0]==3),F(1,9))
        self.assertTrue(all(not c.avoid and not c.penalized for _,c in outcomes))
        self.assertTrue(all(all(card[0] not in (0,1,2) for card in c.board) for _,c in outcomes))

    def test_lifetime_and_boost(self):
        for lifetime,expected in [('board',F(1,6)),('run',F(1,12))]:
            m=self.model(boost=1,lifetime=lifetime)
            s=m.state([0,1,2],2,reroll=1)
            child=next(c for _,c in m.outcomes(s,('reroll',-1)) if [x[0] for x in c.board]==[4,4,4])
            outcomes=list(m.outcomes(child,('select',0)))
            self.assertEqual(sum(p for p,c in outcomes if c.board[0][0]==3),expected)
        m=self.model(boost=4,penalty=1)
        s=m.state([0,1,2],2,owned=[1,0,0,0,0,0])
        outcomes=list(m.outcomes(s,('select',1)))
        # Families 0 and 1 now have a boost: weights [4,4,1,4,1,1].
        self.assertEqual(sum(p for p,c in outcomes if c.board[0][0]==3),F(4,15))

    def test_exact_optimal_reroll(self):
        m=WeightedModel([1]*4,[1,0,0,0],boost=1,penalty=1,lifetime='board',exclude_current=True)
        s=m.state([1,2,3],1,reroll=1)
        solver=Solver(m)
        self.assertEqual(solver.solve(s),(1,0,-1))
        self.assertEqual(solver.decisions[s],('reroll',-1))


if __name__=='__main__':
    unittest.main()
