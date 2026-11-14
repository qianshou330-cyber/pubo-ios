"""Source contracts only; no substitute for Simulator stage traces or pixels."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class MediaDiagnosticsTests(unittest.TestCase):
    def test_fixed_stages_are_debug_ui_test_only(self):
        s = (ROOT / 'App/Components/TimelineMedia.swift').read_text()
        block = s.split('static func emit(_ stage: Stage) {', 1)[1].split('\n}', 1)[0]
        self.assertIn('#if DEBUG', block)
        self.assertIn('contains("--ui-testing")', block)
        self.assertIn('stage.rawValue', block)
        self.assertNotIn('absoluteString', block)
        self.assertNotIn('session.', block)
        self.assertIn('enum Stage: String', s)

    def test_real_generator_failure_publishes_unavailable(self):
        s = (ROOT / 'App/Components/PublicMediaPoster.swift').read_text()
        self.assertIn('if !Task.isCancelled && epoch == session.generation {\n                    failed = true; evidence = "unavailable"', s)
        self.assertIn('PublicMediaDiagnostics.emit(.generatorFailed)', s)
        self.assertIn('await VideoPosterBudget.shared.release()', s)
        self.assertIn('try await Task.sleep(for: .seconds(8))', s)

    def test_collection_is_video_only_and_does_not_override_result(self):
        s = (ROOT / 'scripts/simulator-tests.py').read_text()
        block = s.split("if shard == 'video-poster':", 1)[1].split('if focused:', 1)[0]
        self.assertIn('com.pubo.media.diagnostics', block)
        self.assertIn("timeout=60", block)
        self.assertNotIn('test_exit =', block)
        self.assertIn('finally:', s[:s.index("if shard == 'video-poster':")])

    def test_video_gate_remains_four_pixel_proven_cases(self):
        s = (ROOT / 'UITests/PublicVideoPosterUITests.swift').read_text()
        self.assertEqual(s.count('    func test'), 4)
        self.assertIn('XCTAssertGreaterThan(redFraction, 0.35', s)
        self.assertIn('waitForExpectations(timeout: 15)', s)

if __name__ == '__main__': unittest.main()
