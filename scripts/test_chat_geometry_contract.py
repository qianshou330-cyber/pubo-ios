import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ChatGeometryContractTests(unittest.TestCase):
    def test_room_scroll_container_owns_unchanged_insets(self):
        room = (ROOT / 'App/Features/RoomChatView.swift').read_text()
        timeline = room.split('private var timeline:', 1)[1].split('private func positionTimeline', 1)[0]
        self.assertIn('.contentMargins(.horizontal, 16, for: .scrollContent)', timeline)
        self.assertIn('.scrollTargetLayout()', timeline)
        self.assertIn('.scrollTargetLayout().padding(.bottom, 16)', timeline)
        self.assertIn('.padding(.top, index == 0 && !hasMore && !(loadError != nil && !messages.isEmpty) ? 16 : 0).id(message.id)', timeline)
        self.assertIn('anchor: scrollAnchor', timeline)
        self.assertIn('nearBottom = bottom <= viewport.size.height + 80', timeline)
        self.assertIn('.accessibilityIdentifier("room.avatar." + message.id)', room)

    def test_header_insets_and_endpoint_minimum_are_not_weakened(self):
        room = (ROOT / 'App/Features/RoomChatView.swift').read_text()
        self.assertIn('}.padding(.top, 16)', room)
        self.assertIn('.padding(.top, loadError != nil && !messages.isEmpty ? 0 : 16)', room)
        helper = (ROOT / 'UITests/AppNavigationUITestSupport.swift').read_text()
        self.assertIn('frame.maxX >= requiredX && frame.maxY >= requiredY', helper)
        self.assertIn('requiredX > frame.minX, requiredY > frame.minY', helper)
        self.assertIn('frame.maxX.isFinite, frame.maxY.isFinite', helper)

    def test_avatar_touch_shape_includes_full_44pt_label(self):
        for name in ['ChatView.swift', 'RoomChatView.swift']:
            text = (ROOT / 'App/Features' / name).read_text()
            self.assertIn('size: 42).frame(width: 44, height: 44).contentShape(Rectangle())', text)

    def test_runtime_inset_and_retry_proofs_are_actual_geometry(self):
        alignment = (ROOT / 'UITests/ChatAlignmentUITests.swift').read_text()
        for required in ['firstRowAtTop: true, stage: "initial-', 'firstRowAtTop: false, stage: "context-',
                         'firstRowAtTop: true, stage: "latest-', 'avatar.frame', 'viewport.frame',
                         'composer.frame.minY', 'geometry.lifetime = .keepAlways']:
            self.assertIn(required, alignment)
        composer = (ROOT / 'UITests/ChatComposerParityUITests.swift').read_text()
        for required in ['viewport.swipeUp()', 'viewport.swipeDown()',
                         'retry.frame.minY < viewport.frame.minY', 'frame.maxY <= min(bounds.maxY, composer.frame.minY)',
                         'puboTouchRectMeetsMinimum(frame)', 'revealRetry(app, prefix: prefix, retry: retry)',
                         'retry.tap()', 'retry.waitForNonExistence(timeout: 8)', 'label CONTAINS %@',
                         'https://example.com/pubo-chat-fixture']:
            self.assertIn(required, composer)
        self.assertEqual(composer.count('retry.tap()'), 2)  # timeline retry plus link retry; no repeated link tap

    def test_tab_readiness_has_bounded_real_hit_and_no_coordinate_fallback(self):
        source = (ROOT / 'UITests/AppNavigationUITestSupport.swift').read_text()
        tab = source.split('func puboSelectTab(', 1)[1].split('func puboTapVisible(', 1)[0]
        self.assertIn('isHittable == true', tab)
        self.assertIn('timeout: 8', tab)
        self.assertLess(tab.index('guard result == .completed'), tab.index('button.tap()'))
        self.assertIn('XCTAssertTrue(button.isSelected', tab)
        self.assertNotIn('coordinate(', tab)


if __name__ == '__main__':
    unittest.main()
