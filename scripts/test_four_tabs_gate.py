import unittest
from four_tabs_gate import EXPECTED_TESTS, complete, declared_tests


class FourTabsGateTests(unittest.TestCase):
    def test_exact_declared_scope(self):
        names = declared_tests()
        self.assertEqual(len(names), EXPECTED_TESTS)
        self.assertEqual(len(names), len(set(names)))

    def test_chat_detail_and_transient_menu_use_real_navigation(self):
        from pathlib import Path
        source = Path('UITests/FourTabNavigationUITests.swift').read_text()
        helper = source.split('private func backFromChat', 1)[1].split('private func openRequests', 1)[0]
        self.assertIn('back(app)', helper)
        self.assertIn('waitForNonExistence', helper)
        self.assertIn('tabButton(app, "消息").isSelected', helper)
        menu = source.split('if id == "messages.scan"', 1)[1].split('return', 1)[0]
        self.assertIn('let item = app.buttons[id]', menu)
        self.assertIn('isHittable == true', menu)
        self.assertIn('item.tap()', menu)
        self.assertNotIn('swipeUp()', menu)

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
