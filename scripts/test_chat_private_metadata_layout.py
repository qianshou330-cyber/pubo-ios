"""Source wiring only. Actual 44pt/frame/visual proof belongs to XCTest."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class PrivateMetadataLayoutTests(unittest.TestCase):
    def test_metadata_contains_no_touch_target(self):
        source = (ROOT/'App/Features/ChatView.swift').read_text()
        row = source.split('    private func bubble(', 1)[1].split('    private func messageOverflow(', 1)[0]
        metadata = row.split('                HStack(spacing: 6) {', 1)[1].split('if !message["reactions"]', 1)[0]
        for original in ['ChatRelativeTime(date: date)', '"已读"', '"已发送"', '"已编辑"']:
            self.assertIn(original, metadata)
        for forbidden in ['Menu {', 'Button', 'height: 44', '.overlay']:
            self.assertNotIn(forbidden, metadata)
        self.assertIn('if own { messageOverflow(message, own: own) }', row)
        self.assertIn('if !own { messageOverflow(message, own: own) }', row)
        self.assertIn('HStack(alignment: .bottom, spacing: 4)', row)

    def test_menu_keeps_real_shape_identifier_and_shared_actions(self):
        source = (ROOT/'App/Features/ChatView.swift').read_text()
        menu = source.split('    private func messageOverflow(', 1)[1].split('    private func messageMenu(', 1)[0]
        for required in ['Menu { messageMenu(message, own: own) }', '.frame(width: 44, height: 44)', '.contentShape(Rectangle())', '.buttonStyle(.plain)', '.accessibilityLabel("消息菜单")', '.accessibilityIdentifier("chat.menu." + message.id)']:
            self.assertIn(required, menu)
        self.assertNotIn('.overlay', menu)
        self.assertNotIn('.offset', menu)

    def test_existing_both_theme_test_measures_real_frames(self):
        source = (ROOT/'UITests/ChatAlignmentUITests.swift').read_text()
        helper = source.split('private func assertPrivateMetadataLayout(', 1)[1].split('private func room(', 1)[0]
        for required in ['"private0001", "private0002"', 'menu.frame', 'bubble.frame', 'metadata.frame', 'puboTouchRectMeetsMinimum(target)', 'menu.isHittable', 'target.intersects(body)', 'target.intersects(details)', 'XCTAssertLessThan(details.height, 44', 'geometry.lifetime = .keepAlways', 'XCTWaiter.wait(for: [settled], timeout: 8)', 'XCTAssertEqual(result, .completed']:
            self.assertIn(required, helper)
        scenario = source.split('func testPrivateSearchDateAndReactionsBothThemes()',1)[1].split('func testGroupSearch',1)[0]
        self.assertIn('for dark in [false, true]',scenario)
        self.assertIn('assertPrivateMetadataLayout(app, theme: theme)',scenario)
        self.assertIn('app.buttons["添加反应 ❤"].tap()',scenario)
        self.assertIn('menu.tap()', scenario)
        self.assertIn('details.tap()', scenario)
        self.assertIn('sheet.waitForNonExistence(timeout: 6)', scenario)
        self.assertIn('app.buttons["取消反应 ❤"].tap()',scenario)

if __name__ == '__main__': unittest.main()
