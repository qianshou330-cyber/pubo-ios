import unittest
from four_tabs_gate import EXPECTED_TESTS, complete, declared_tests


class FourTabsGateTests(unittest.TestCase):
    def test_exact_declared_scope(self):
        names = declared_tests()
        self.assertEqual(len(names), EXPECTED_TESTS)
        self.assertEqual(len(names), len(set(names)))

    def test_only_complete_pass_is_accepted(self):
        good = dict(passedTests=EXPECTED_TESTS, failedTests=0, skippedTests=0, expectedFailures=0)
        self.assertTrue(complete(good))
        for key in good:
            bad = dict(good)
            bad[key] = good[key] + 1
            self.assertFalse(complete(bad))
            del bad[key]
            self.assertFalse(complete(bad))
        self.assertFalse(complete({}))
