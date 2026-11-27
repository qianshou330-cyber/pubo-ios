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
                      'frame.height > 0', 'window.intersects(frame)'):
            self.assertIn(token, self.tab)
        # C60 caches the one native hittability read for deferred diagnostics.
        # Require the complete geometry conjunction to gate that read, rather
        # than the former guard/return spelling. Invalid geometry retains nil
        # and cannot satisfy the final cached Boolean proof.
        predicate = self.tab.split('let ready = XCTNSPredicateExpectation', 1)[1].split('let result = XCTWaiter.wait', 1)[0]
        self.assertIn('let intersects = finite && windowPositive && framePositive && window.intersects(frame)', predicate)
        self.assertIn('var hittable: Bool? = nil', predicate)
        self.assertIn('if intersects {', predicate)
        self.assertIn('hittable = button.isHittable == true', predicate)
        self.assertIn('return hittable == true', predicate)
        self.assertEqual(predicate.count('button.isHittable'), 1)
        self.assertLess(predicate.index('if intersects {'), predicate.index('hittable = button.isHittable == true'))
        self.assertLess(predicate.index('hittable = button.isHittable == true'), predicate.index('return hittable == true'))
        self.assertNotIn('return true', predicate)

    def test_single_unchanged_readiness_budget(self):
        self.assertIn('waitForExistence(timeout: 20)', self.tab)
        self.assertEqual(self.tab.count('timeout: 8'), 1)
        self.assertEqual(self.tab.count('XCTWaiter.wait(for: [ready], timeout: 8)'), 1)
        self.assertEqual(self.tab.count('XCTWaiter.wait(for: [selected], timeout: 5)'), 1)
        self.assertEqual(self.tab.count('XCTWaiter.wait('), 2)
        self.assertIn('XCTAssertEqual(result, .completed', self.tab)

    def test_real_click_and_selected_proof_remain_required(self):
        self.assertLess(self.tab.index('guard result == .completed'), self.tab.index('button.tap()'))
        self.assertLess(self.tab.index('button.tap()'), self.tab.index('XCTWaiter.wait(for: [selected], timeout: 5)'))
        self.assertLess(self.tab.index('XCTWaiter.wait(for: [selected], timeout: 5)'), self.tab.index('XCTAssertTrue(button.isSelected'))
        self.assertEqual(self.tab.count('button.tap()'), 1)
        self.assertIn('XCTAssertTrue(button.isSelected', self.tab)
        for forbidden in ('coordinate(', 'app.launch()', 'app.activate()', 'sleep(', 'if button.isSelected'):
            self.assertNotIn(forbidden, self.tab)

if __name__ == '__main__': unittest.main()
