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
        original = {key: SHARDS[key] for key in ('social-actions', 'social-settings', 'authentication', 'baseline')}
        self.assertEqual(sum(count for count, _ in original.values()), 86)
        selected = [s for _, suites in original.values() for s in suites]
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
    def test_chat_pilot_exact_methods_and_disjoint_original_coverage(self):
        expected = {
            'testAnimatedReactionKeepsRatioAndPlaysAtLargeTextSize',
            'testGroupDraftSurvivesTabsAndKeyboard',
            'testGroupReactionDoesNotUseDirectMessagePermission',
            'testGroupSearchExactMessageReportAndMenuBothThemes',
            'testLargeTextGroupComposerAndTabsStayReachable',
            'testMixedConversationsAndHomeTabsBothThemes',
            'testPrivateSearchDateAndReactionsBothThemes',
            'testReportUnknownOutcomeDisablesResubmission',
            'testStaleOtherParticipantReactionCannotCancelExistingMine',
        }
        source = (pathlib.Path(__file__).resolve().parents[1] / 'UITests/ChatAlignmentUITests.swift').read_text()
        methods = re.findall(r'^\s+func (test\w+)\(', source, re.M)
        self.assertEqual(len(methods), 9)
        self.assertEqual(set(methods), expected)
        self.assertEqual(selection('chat-alignment'), (9, ['-only-testing:PUBOUITests/ChatAlignmentUITests']))
        selected = [s for _, suites in SHARDS.values() for s in suites]
        self.assertEqual(len(selected), len(set(selected)))
        self.assertEqual(sum(count for count, _ in SHARDS.values()), 95)
        self.assertFalse(any(name.startswith('ChatAlignmentUITests/') for name in FOCUSED))

    def test_chat_pilot_workflow_keeps_independent_execution_and_formal_gate(self):
        workflow = (pathlib.Path(__file__).resolve().parents[1] / '.github/workflows/four-tabs.yml').read_text()
        pilot = workflow.split('  chat-alignment:\n', 1)[1].split('  package:\n', 1)[0]
        for required in ('    needs: checks', '      fail-fast: false',
                         '        size: [small, large]', '    timeout-minutes: 65',
                         "          PUBO_UI_SHARD: 'chat-alignment'", "          PUBO_PREBUILT_TESTS: '1'",
                         '          PUBO_SIM_SIZE: ${{ matrix.size }}',
                         'python3 scripts/simulator-tests.py', 'set -o pipefail',
                         '        if: always()', '            build/ui-*.xcresult',
                         '            build/screenshots/', '            build/chat-alignment-tests.log'):
            self.assertIn(required, pilot)
        self.assertNotIn('PUBO_REGRESSION_147_ONLY', pilot)
        self.assertNotIn('skip-testing', pilot)
        self.assertIn('    needs: [checks, ocr-validation, navigation, legacy-regression, chat-alignment]', workflow)
        candidate = workflow.split('  candidate-package:', 1)[1]
        self.assertIn('    needs: checks', candidate)
        self.assertIn('QA-INCOMPLETE', candidate)

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
