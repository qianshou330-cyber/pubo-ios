"""Static safeguards; real geometry is asserted by the existing composer UI tests."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class ChatHorizontalInsetsContract(unittest.TestCase):
    def test_private_axis_split_without_viewport_shrink_or_scroll_change(self):
        source = (ROOT / 'App/Features/ChatView.swift').read_text()
        block = source.split('private var messageList:', 1)[1].split('private func positionTimeline', 1)[0]
        self.assertIn('.scrollTargetLayout().padding(.vertical, 16)', block)
        self.assertIn('ScrollView { messageList }.contentMargins(.horizontal, 16, for: .scrollContent)', block)
        self.assertIn('anchor: scrollAnchor', block)
        self.assertIn('nearBottom = bottom <= viewport.size.height + 80', block)
        self.assertNotIn('.padding(.horizontal', block)
        self.assertIn('.accessibilityIdentifier("chat.avatar." + message.id)', source)

    def test_real_visible_frames_no_gate_scroll_or_empty_success(self):
        source = (ROOT / 'UITests/ChatComposerParityUITests.swift').read_text()
        block = source.split('private func assertTimelineHorizontalInsets(', 1)[1].split('private func backToHome(', 1)[0]
        for text in ['app.scrollViews[prefix + ".timeline"]', '!frames.isEmpty', 'frames.allSatisfy',
                     'frame.minX - bounds.minX - 16', 'frame.maxY <= min(bounds.maxY, composerFrame.minY)',
                     'app.debugDescription', 'tabs.allElementsBoundByIndex', 'avatars.allElementsBoundByIndex',
                     'proof.lifetime = .keepAlways', 'XCTAssertEqual(result, .completed']:
            self.assertIn(text, block)
        selection = block.split('let frames = avatarSnapshots.map', 1)[1].split('let valid =', 1)[0]
        self.assertNotIn('frame.minX', selection)
        self.assertNotIn('frame.maxX', selection)
        self.assertNotIn('puboTouchDimensionMeetsMinimum', selection)
        validation = block.split('let valid =', 1)[1].split('return valid', 1)[0]
        self.assertIn('puboTouchRectMeetsMinimum(frame)', validation)
        self.assertIn('frame.minX >= bounds.minX && frame.maxX <= bounds.maxX', validation)
        self.assertNotIn('.swipe', block)
        self.assertNotIn('.tap()', block)
        for stage in ['ordinary-', 'keyboard-', 'draft-restored-']:
            self.assertIn('assertTimelineHorizontalInsets(app, room: room, stage: "' + stage, source)
        self.assertEqual(source.count('    func test'), 8)  # existing 4 composer + 4 state methods

    def test_single_current_snapshot_per_poll_and_errors_never_pass(self):
        source = (ROOT / 'UITests/ChatComposerParityUITests.swift').read_text()
        block = source.split('private func assertTimelineHorizontalInsets(', 1)[1].split('private func backToHome(', 1)[0]
        poll = block.split('let settled =', 1)[1].split('}, object: nil)', 1)[0]
        self.assertEqual(poll.count('try app.snapshot()'), 1)
        for remote in ['viewport.frame', 'composer.frame', 'allElementsBoundByIndex', 'isHittable']:
            self.assertNotIn(remote, poll)
        self.assertIn('puboSnapshotDescendants(tree)', poll)
        self.assertIn('catch {', poll)
        self.assertIn('snapshotError=', poll)
        self.assertIn('return false', poll.split('catch {', 1)[1])
        self.assertIn('timeout: 8', block)
        helper = (ROOT / 'UITests/AppNavigationUITestSupport.swift').read_text()
        flatten = helper.split('func puboSnapshotDescendants(', 1)[1].split('/// Navigate', 1)[0]
        self.assertIn('snapshot.children.flatMap', flatten)
        self.assertNotIn('.snapshot()', flatten)

    def test_host_preflight_logs_are_preserved_without_simulator_claim(self):
        workflow = (ROOT / '.github/workflows/four-tabs.yml').read_text()
        self.assertIn('Darwin gate host preflight (not Simulator proof)', workflow)
        self.assertIn('bash scripts/check_chat_gate_macos.sh 2>&1 | tee build/chat-gate-preflight.log', workflow)
        self.assertIn('            build/chat-gate-preflight.log', workflow)

if __name__ == '__main__': unittest.main()
