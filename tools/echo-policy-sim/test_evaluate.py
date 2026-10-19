"""Aggregation, frozen selection and paired-interval tests; no Lua dependency."""
import importlib.util
import pathlib
import unittest

spec=importlib.util.spec_from_file_location('evaluate',pathlib.Path(__file__).with_name('evaluate.py'))
E=importlib.util.module_from_spec(spec);spec.loader.exec_module(E)


def row(policy,seed,complete,missing,profile='p',scenario='case'):
    return dict(profile=profile,scenario=scenario,seed=str(seed),policy=policy,
                complete=str(complete),missing=str(missing),select='1',banish='0',reroll='0',
                freeze='0',draws='0',actions='1',stop='COMPLETE' if complete else 'PICKS_EXHAUSTED')


class ProtocolTests(unittest.TestCase):
    def test_completion_outranks_missing_and_cost(self):
        a=E.bucket();b=E.bucket()
        a.update(n=100,complete=20,missing=900,actions=1000)
        b.update(n=100,complete=19,missing=1,actions=1)
        self.assertEqual(E.rank({'a':a,'b':b})[0],'a')

    def test_selection_cannot_see_holdout(self):
        training=E.Results()
        training.add(row('released',1,0,1));training.add(row('candidate',1,1,0))
        chosen=E.select(training)
        evaluation=E.Results()
        evaluation.add(row('released',100001,1,0));evaluation.add(row('candidate',100001,0,1))
        self.assertEqual(chosen['primary'],'candidate')
        self.assertEqual(E.paired_interval(evaluation,chosen['primary'])['mean'],-1)
        self.assertIsNone(E.paired_interval(evaluation,chosen['primary'])['low'])

    def test_cluster_correlated_scenarios_by_seed(self):
        results=E.Results()
        for seed in range(1,101):
            for case in ('one','two','three'):
                results.add(row('released',seed,0,1,scenario=case))
                results.add(row('candidate',seed,seed%2,1-seed%2,scenario=case))
        ci=E.paired_interval(results,'candidate')
        self.assertEqual(ci['seed_blocks'],100)
        self.assertEqual(ci['mean'],0.5)
        self.assertGreater(ci['high']-ci['mean'],0.09)

    def test_missing_copies_and_resource_counts_are_separate(self):
        result=E.Results()
        result.add(row('released',1,0,3))
        result.add(row('candidate',1,0,1))
        self.assertEqual(E.paired_interval(result,'candidate','missing')['mean'],-2)
        self.assertEqual(result.total['candidate']['banish'],0)

    def test_unsettled_trial_fails(self):
        invalid=row('released',1,0,1);invalid['stop']='ACTION_LIMIT'
        with self.assertRaises(AssertionError): E.Results().add(invalid)


if __name__=='__main__': unittest.main()
