import unittest
from plan_study import aggregate, paired


class ProtocolTests(unittest.TestCase):
    def rows(self):
        rows=[]
        for seed in range(1,5):
            for policy in ('candidate','base'):
                for scenario in ('a','b'):
                    complete=int(policy=='candidate' and seed==1)
                    rows.append(dict(seed=str(seed),policy=policy,scenario=scenario,profile='none',
                        complete=str(complete),missing=str(1-complete),banish='1',reroll='2',freeze='0',actions='4'))
        return rows

    def test_clusters_not_individual_cells(self):
        r=paired(self.rows(),'candidate','base')
        self.assertEqual(r['seed_clusters'],4)
        self.assertEqual(r['delta'],0.25)
        self.assertEqual(r['wins'],2)
        self.assertEqual(r['losses'],0)
        self.assertAlmostEqual(r['ci95'][1]-r['delta'],0.49)

    def test_accounting(self):
        r=aggregate(self.rows(),'candidate')
        self.assertEqual((r['runs'],r['complete'],r['missing']),(8,2,0.75))
        self.assertEqual((r['banish'],r['reroll'],r['freeze']),(1,2,0))

    def test_control_identity(self):
        r=paired(self.rows(),'base','base')
        self.assertEqual(r['delta'],0)
        self.assertEqual(r['ci95'],[0,0])


if __name__=='__main__':
    unittest.main()
