"""Static guardrails; real layout/accessibility must pass the unchanged video shard."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class VideoPlaceholderLayoutTests(unittest.TestCase):
    def test_video_owns_playback_glyph(self):
        s = (ROOT / 'App/Components/PublicMediaPoster.swift').read_text()
        self.assertIn('private var playbackGlyph: some View', s)
        self.assertIn('VStack(spacing: 8) {\n                    playbackGlyph\n                    Text(failed ?', s)
        self.assertIn('Image(uiImage: image).resizable().scaledToFit()\n                playbackGlyph', s)
        self.assertIn('media.poster.status.', s)
        self.assertIn('media.poster.playGlyph.', s)

    def test_outer_overlay_is_audio_only_and_action_is_preserved(self):
        s = (ROOT / 'App/Components/TimelineMedia.swift').read_text()
        self.assertIn('if mime.hasPrefix("audio/") {\n                            Image(systemName: "play.fill")', s)
        self.assertIn('Button { preview = true } label:', s)
        self.assertIn('.sheet(isPresented: $preview)', s)

    def test_unavailable_geometry_is_added_without_relaxing_existing_gate(self):
        s = (ROOT / 'UITests/PublicVideoPosterUITests.swift').read_text()
        self.assertEqual(s.count('    func test'), 4)
        self.assertIn('waitForExpectations(timeout: 15)', s)
        self.assertIn('XCTAssertGreaterThan(redFraction, 0.35', s)
        self.assertIn('posterFrame.contains(statusFrame)', s)
        self.assertIn('posterFrame.contains(glyphFrame)', s)
        self.assertIn('statusFrame.minY, glyphFrame.maxY + 4', s)
        self.assertIn('app.buttons["media.open.posterfixture"].isHittable', s)

if __name__ == '__main__': unittest.main()
