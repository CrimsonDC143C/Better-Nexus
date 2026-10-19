import unittest
from fractions import Fraction as F
from optimal import Model, Solver, SearchLimit, InvalidModel, benchmarks


class OptimalTests(unittest.TestCase):
    def test_analytic_search(self):
        m = Model([1, 3], [1, 0])
        for b, r, expected in [(1, 0, F(1, 4)), (0, 1, F(37, 64)), (1, 1, F(175, 256))]:
            s = m.state([1, 1, 1], 1, banish=b, reroll=r)
            solver = Solver(m)
            self.assertEqual(solver.solve(s)[0], expected)
            if b and r:
                self.assertEqual(solver.decisions[s], ("reroll", -1))
                self.assertEqual(solver.solve(s)[2], -F(91, 64))

    def test_freeze_is_useful_without_banish(self):
        for name, m, s in benchmarks()[3:]:
            with self.subTest(name=name):
                solver = Solver(m)
                self.assertEqual(solver.solve(s), (F(1), F(0), F(-1)))
                self.assertEqual(solver.decisions[s][0], "freeze")
                self.assertLess(Solver(m).solve(__import__('dataclasses').replace(s, freeze=0))[0], 1)

    def test_all_outcomes_mass_and_resource_decrease(self):
        for exclusion in ("none", "spell", "family"):
            m = Model([1, 2, 3, 4, 5], [1, 1, 0, 0, 0], exclusion=exclusion, unique=True, cap=2)
            s = m.state([0, 2, 3], 2, 1, 1, 1)
            for action in m.actions(s):
                outcomes = list(m.outcomes(s, action))
                self.assertEqual(sum(p for p, _ in outcomes), 1)
                for probability, child in outcomes:
                    self.assertGreater(probability, 0)
                    self.assertEqual(child.picks + child.banish + child.reroll + child.freeze, 4)
                    if not m.terminal(child):
                        self.assertEqual(len(set(c[0] for c in child.board)), 3)

    def test_guards(self):
        m = Model([1, 1, 1], [1, 0, 0])
        s = m.state([(0, False, False), (1, True, False), (2, True, True)], 1, 1, 1, 1)
        self.assertEqual(m.actions(s), (("select", 0), ("select", 1), ("select", 2), ("freeze", 0)))
        with self.assertRaises(InvalidModel):
            list(m.outcomes(s, ("banish", 0)))

    def test_exhaustion_and_limit_fail_closed(self):
        m = Model([1, 1], [1, 0], [0, 0], "family")
        with self.assertRaises(InvalidModel):
            Solver(m).certificate(m.state([1, 1, 1], 1, banish=1))
        m = Model([1, 1], [1, 0])
        with self.assertRaises(SearchLimit):
            Solver(m, limit=1).certificate(m.state([1, 1, 1], 2, reroll=1))

    def test_terminal(self):
        m = Model([1, 1], [2, 0])
        self.assertEqual(Solver(m).solve(m.state([1, 1, 1], 0)), (0, -2, 0))
        self.assertEqual(Solver(m).solve(m.state([1, 1, 1], 3, owned=[2, 0])), (1, 0, 0))


if __name__ == "__main__":
    unittest.main()
