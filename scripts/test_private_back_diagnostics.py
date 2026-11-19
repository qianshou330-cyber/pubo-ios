from pathlib import Path
import re
import unittest
from ui_selection import selection

ROOT = Path(__file__).resolve().parents[1]


class PrivateBackDiagnosticTests(unittest.TestCase):
    def test_cases_are_independent_and_match_the_swift_methods(self):
        swift = (ROOT / 'UITests/PrivateNativeBackIsolationUITests.swift').read_text()
        expected = {
            'without-picker': 'testDarkPrivateSecondNativeBackWithoutPicker',
            'after-picker': 'testDarkPrivateSecondNativeBackAfterPicker',
        }
        self.assertEqual(set(re.findall(r'func (test\w+)\(', swift)), set(expected.values()))
        for scenario, case in expected.items():
            self.assertEqual(selection('private-back-' + scenario),
                             (1, ['-only-testing:PUBOUITests/PrivateNativeBackIsolationUITests/' + case]))
        for literal in ['if afterPicker && visit == 1', 'for visit in 1...2',
                        'app.navigationBars.buttons.element(boundBy: 0)', 'waitForExistence(timeout: 8)',
                        'run(afterPicker: false)', 'run(afterPicker: true)']:
            self.assertIn(literal, swift)

    def test_diagnostic_does_not_replace_or_gate_existing_package(self):
        workflow = (ROOT / '.github/workflows/four-tabs.yml').read_text()
        diagnostic = workflow.split('  diagnostic-private-back:\n', 1)[1].split('  video-poster:\n', 1)[0]
        self.assertIn('scenario: [without-picker, after-picker]', diagnostic)
        self.assertIn('fail-fast: false', diagnostic)
        self.assertIn('PUBO_SIM_SIZE: large', diagnostic)
        self.assertIn("PUBO_UI_SHARD: 'private-back-${{ matrix.scenario }}'", diagnostic)
        package_needs = workflow.split('  package:\n', 1)[1].split('runs-on:', 1)[0]
        self.assertIn('chat-presentation', package_needs)
        self.assertNotIn('diagnostic-private-back', package_needs)

    def test_runner_wires_video_and_existing_passive_receipt(self):
        runner = (ROOT / 'scripts/simulator-tests.py').read_text()
        self.assertIn('Private Back comparison requires the iPhone Max', runner)
        self.assertIn('private-native-back.mp4', runner)
        self.assertIn("if shard == 'chat-presentation-composer' or private_back_probe:", runner)
        self.assertIn('not focused and not private_back_probe', runner)
