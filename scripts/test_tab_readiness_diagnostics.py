"""Source invariants, not a replacement for Xcode/UI execution."""
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / 'UITests/AppNavigationUITestSupport.swift').read_text()
BODY = SOURCE.split('func puboSelectTab(', 1)[1].split('func puboTapVisible(', 1)[0]
PREDICATE = BODY.split('let ready = XCTNSPredicateExpectation', 1)[1].split('let result = XCTWaiter.wait', 1)[0]

class ReadinessDiagnosticsTests(unittest.TestCase):
    def test_original_budgets(self):
        self.assertEqual(BODY.count('waitForExistence(timeout: 20)'), 1)
        self.assertEqual(BODY.count('XCTWaiter.wait(for: [ready], timeout: 8)'), 1)
    def test_no_extra_ax_queries(self):
        for query in ['app.windows.firstMatch.frame', 'button.frame', 'button.isHittable']:
            self.assertEqual(PREDICATE.count(query), 1)
        for forbidden in ['snapshot(', 'debugDescription', 'isSelected', 'screenshot(', 'sleep(', '.tap()']:
            self.assertNotIn(forbidden, PREDICATE)
    def test_buffer_only_in_predicate(self):
        self.assertNotIn('print(', PREDICATE)
        self.assertIn('samples.count < 16', PREDICATE)
        self.assertIn('samples.reserveCapacity(16)', BODY)
    def test_original_real_action_and_assertions(self):
        self.assertEqual(BODY.count('button.tap()'), 1)
        self.assertIn('XCTAssertEqual(result, .completed', BODY)
        self.assertIn('guard result == .completed else { return }', BODY)
        self.assertIn('XCTAssertTrue(button.isSelected', BODY)
    def test_preserved_short_circuit(self):
        self.assertIn('finite && windowPositive && framePositive && window.intersects(frame)', PREDICATE)
        self.assertIn('if intersects {', PREDICATE)
        self.assertIn('return hittable == true', PREDICATE)
        for finite in [False, True]:
            for wp in [False, True]:
                for fp in [False, True]:
                    for intersect in [False, True]:
                        for hit in [False, True]:
                            old = finite and wp and fp and intersect and hit
                            queried = hit if finite and wp and fp and intersect else None
                            self.assertEqual(old, queried is True)
    def test_all_query_phases_and_timings(self):
        for field in ['window-frame', 'button-frame', 'button-hittable', 'sample-complete',
                      'windowSeconds=', 'frameSeconds=', 'hitSeconds=', 'not-queried']:
            self.assertIn(field, BODY)

if __name__ == '__main__':
    unittest.main()
