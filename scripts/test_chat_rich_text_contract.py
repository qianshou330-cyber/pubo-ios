"""Source-only guardrails, NOT a substitute for UIKit layout/runtime tests."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ChatRichTextContractTests(unittest.TestCase):
    def test_chat_passes_swiftui_scaled_size_explicitly(self):
        source = (ROOT / "App/Components/ChatMessageContent.swift").read_text()
        self.assertIn("@ScaledMetric(relativeTo: .subheadline) private var messagePointSize: CGFloat = 12.6", source)
        self.assertIn("pointSizeOverride: messagePointSize", source)

    def test_existing_notes_keep_the_default_metrics_path(self):
        source = (ROOT / "App/Components/RichNoteText.swift").read_text()
        self.assertIn("var pointSizeOverride: CGFloat? = nil", source)
        self.assertIn("pointSizeOverride.map { UIFont.systemFont(ofSize: $0) }", source)
        self.assertIn("?? UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: UIFont.systemFont(ofSize: 12.6))", source)
        self.assertIn("view.adjustsFontForContentSizeCategory = pointSizeOverride == nil", source)
        self.assertNotIn("pointSizeOverride:", (ROOT / "App/Components/CommonViews.swift").read_text())

    def test_render_key_and_emoji_layout_follow_resolved_font(self):
        source = (ROOT / "App/Components/RichNoteText.swift").read_text()
        self.assertIn("String(describing: font.pointSize)", source)
        self.assertIn("let height = font.pointSize *", source)
        self.assertIn("size: font.pointSize", source)

    def test_actual_geometry_guard_keeps_accessible_message_content(self):
        source = (ROOT / "App/Components/RichNoteText.swift").read_text()
        # Actual C17 AX output exposes text in the bubble value; do not replace
        # that with a test font diagnostic and break readable message content.
        self.assertNotIn("view.accessibilityValue =", source)
        test = (ROOT / "UITests/ChatAlignmentUITests.swift").read_text()
        self.assertIn('app.staticTexts["room.bubble.room0003"]', test)
        self.assertIn('XCTAssertEqual(body.value as? String, "今天一起分享喜欢的舞台。")', test)
        self.assertIn('XCTAssertEqual(body.textViews.count, 1)', test)
        self.assertIn('XCTAssertGreaterThan(renderedBody.frame.height, 22', test)


if __name__ == "__main__":
    unittest.main()
