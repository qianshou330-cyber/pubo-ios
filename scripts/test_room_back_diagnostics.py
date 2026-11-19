from pathlib import Path
import re
import unittest
from ui_selection import selection, PRESENTATION_PARTS

ROOT = Path(__file__).resolve().parents[1]

class RoomBackDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.swift = (ROOT / 'UITests/RoomNativeBackIsolationUITests.swift').read_text()
        self.runner = (ROOT / 'scripts/simulator-tests.py').read_text()
        self.workflow = (ROOT / '.github/workflows/four-tabs.yml').read_text()

    def test_exact_independent_arms(self):
        expected = {'without-picker': 'testLightRoomSecondNativeBackWithoutPicker',
                    'after-picker': 'testLightRoomSecondNativeBackAfterPicker'}
        self.assertEqual(set(re.findall(r'func (test\w+)\(', self.swift)), set(expected.values()))
        for arm, method in expected.items():
            self.assertEqual(selection('room-back-' + arm),
                             (1, ['-only-testing:PUBOUITests/RoomNativeBackIsolationUITests/' + method]))
        self.assertEqual(sum(map(len, PRESENTATION_PARTS.values())), 8)

    def test_room_light_synthetic_only(self):
        self.assertIn('["--ui-testing", "--social-align", "--chat-align", "--four-tabs-drafts"]', self.swift)
        for text in ['conversation.room:socialroom', 'room.input', 'room.attachments', '从网盘选择']:
            self.assertIn(text, self.swift)
        for text in ['--dark', '--isolated-backend', 'conversation.user:', 'chat.input']:
            self.assertNotIn(text, self.swift)

    def test_same_two_native_taps_and_unchanged_budget(self):
        for text in ['for visit in 1...2', 'if afterPicker && visit == 1',
                     'app.navigationBars.buttons.element(boundBy: 0)', 'XCTAssertTrue(back.isHittable',
                     'messages.waitForExistence(timeout: 8)', 'XCTAssertEqual(allTabs.count, 4)',
                     'XCTAssertFalse(input.exists', 'for _ in 0..<4 where !row.isHittable']:
            self.assertIn(text, self.swift)
        self.assertEqual(self.swift.count('back.tap()'), 1)
        for text in ['sleep(', 'press(forDuration:', 'coordinate(', 'swipeRight(', 'messagesPath']:
            self.assertNotIn(text, self.swift)

    def test_picker_gate_is_not_skipped_or_retried(self):
        picker = self.swift.split('if afterPicker && visit == 1 {', 1)[1].split('            stage = "visit-\\(visit)-back-target"', 1)[0]
        for text in ['attachments.isHittable', 'attachments.tap()', 'drive.waitForExistence(timeout: 5)',
                     'drive.tap()', 'cancel.waitForExistence(timeout: 5)', 'cancel.tap()', 'input.isHittable']:
            self.assertIn(text, picker)
        self.assertNotIn('continue', picker)

    def test_failed_preconditions_get_post_outcome_capture(self):
        teardown = self.swift.split('override func tearDownWithError()', 1)[1].split('private func run', 1)[0]
        self.assertLess(teardown.index('app.screenshot()'), teardown.index('app.terminate()'))
        self.assertIn('room-native-back-stage', teardown)
        self.assertIn('.keepAlways', teardown)
        self.assertIn('observedApp = app', self.swift)
        tap_segment = self.swift.split('let back = app.navigationBars.buttons.element(boundBy: 0)', 1)[1].split('let restored', 1)[0]
        self.assertNotIn('screenshot', tap_segment)
        self.assertNotIn('debugDescription', tap_segment)

    def test_runner_size_video_and_no_synthetic_post_run(self):
        self.assertIn("room_back_probe and (os.environ.get('PUBO_SIM_SIZE') != 'small' or 'SE' not in selected[0]['name'])", self.runner)
        self.assertIn('Room Back comparison requires the iPhone SE', self.runner)
        self.assertIn('if private_back_probe or room_back_probe:', self.runner)
        self.assertIn('room-native-back.mp4', self.runner)
        self.assertIn('not focused and not private_back_probe and not room_back_probe', self.runner)
        self.assertIn('back_video.send_signal(signal.SIGINT)', self.runner)
        self.assertIn('if elapsed >= 1800:', self.runner)

    def test_counts_are_never_room_lifecycle_or_required_result(self):
        block = self.runner.split('        if room_back_probe:', 1)[1].split("        if shard == 'chat-presentation-states':", 1)[0]
        self.assertIn("'roomLifecycleVerified': False", block)
        self.assertIn('CAPTURED_COUNTS', block)
        self.assertIn('event=leasesChanged', block)
        for text in ['privateTaskEntered', 'test_exit =', "record['tests'] =", 'roomLifecycleVerified\': True']:
            self.assertNotIn(text, block)

    def test_job_is_optional_for_acceptance_and_always_uploads(self):
        job = self.workflow.split('  diagnostic-room-back:\n', 1)[1].split('  video-poster:\n', 1)[0]
        for text in ['scenario: [without-picker, after-picker]', 'fail-fast: false',
                     'PUBO_SIM_SIZE: small', "PUBO_UI_SHARD: 'room-back-${{ matrix.scenario }}'",
                     'if: always()', 'build/ui-*.xcresult', 'build/screenshots/', 'set -o pipefail']:
            self.assertIn(text, job)
        package = self.workflow.split('  package:\n', 1)[1].split('runs-on:', 1)[0]
        self.assertNotIn('diagnostic-room-back', package)
        self.assertIn('chat-presentation', package)
