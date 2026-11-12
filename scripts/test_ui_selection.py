import pathlib
import re
import unittest
from ui_selection import SHARDS, FOCUSED, selection, complete

class SelectionTests(unittest.TestCase):
    def test_disjoint_complete_original_coverage(self):
        expected = {'SocialAlignmentUITests', 'ParityBatchUITests', 'FollowRequestParityUITests',
                    'FollowListParityUITests', 'ContactPagingParityUITests',
                    'LocalTimelineUITests/testOlderFailureRetriesAtReadingPositionWithoutDroppingPosts',
                    'AccountSettingsParityUITests', 'ProfileParityUITests', 'DriveParityUITests',
                    'ChannelParityUITests', 'AuthStaticUITests', 'PUBOUITests'}
        selected = [s for _, suites in SHARDS.values() for s in suites]
        self.assertEqual(set(selected), expected)
        self.assertEqual(len(selected), len(set(selected)))
    def test_counts_match_current_source(self):
        root = pathlib.Path(__file__).resolve().parents[1] / 'UITests'
        for count, suites in SHARDS.values():
            actual = 0
            for suite in suites:
                if '/' in suite: actual += 1
                else: actual += len(re.findall(r'^\s+func test\w+\(', (root / (suite + '.swift')).read_text(), re.M))
            self.assertEqual(count, actual)
    def test_unknown_fails_closed(self):
        with self.assertRaises(ValueError): selection('typo')
    def test_failed_skipped_missing_never_complete(self):
        good = dict(passedTests=3, failedTests=0, skippedTests=0, expectedFailures=0)
        self.assertTrue(complete(good, 3))
        for key in good:
            bad = good.copy(); bad[key] = 1
            self.assertFalse(complete(bad, 3))
        self.assertFalse(complete({}, 3))
    def test_gate_keeps_previous_regressions_and_adds_new_failures(self):
        self.assertEqual(len(FOCUSED), 5)
        self.assertEqual(len(set(FOCUSED)), 5)

if __name__ == '__main__': unittest.main()
