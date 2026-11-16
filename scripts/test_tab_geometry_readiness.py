"""Contract checks only; actual XCTest execution remains mandatory in CI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class TabGeometryReadinessTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'UITests/AppNavigationUITestSupport.swift').read_text()
        self.tab = self.source.split('func puboSelectTab(', 1)[1].split('func puboTapVisible(', 1)[0]

    def test_invalid_window_and_button_geometry_cannot_pass(self):
        for token in ('app.windows.firstMatch.frame', 'button.frame', '$0.isFinite',
                      'window.width > 0', 'window.height > 0', 'frame.width > 0',
                      'frame.height > 0', 'window.intersects(frame)', 'else { return false }'):
            self.assertIn(token, self.tab)
        self.assertLess(self.tab.index('guard finite'), self.tab.index('return button.isHittable == true'))

    def test_single_unchanged_readiness_budget(self):
        self.assertIn('waitForExistence(timeout: 20)', self.tab)
        self.assertEqual(self.tab.count('timeout: 8'), 1)
        self.assertEqual(self.tab.count('XCTWaiter.wait('), 1)
        self.assertIn('XCTAssertEqual(result, .completed', self.tab)

    def test_real_click_and_selected_proof_remain_required(self):
        self.assertLess(self.tab.index('guard result == .completed'), self.tab.index('button.tap()'))
        self.assertEqual(self.tab.count('button.tap()'), 1)
        self.assertIn('XCTAssertTrue(button.isSelected', self.tab)
        for forbidden in ('coordinate(', 'app.launch()', 'app.activate()', 'sleep(', 'if button.isSelected'):
            self.assertNotIn(forbidden, self.tab)

if __name__ == '__main__': unittest.main()
