"""Static integration scope checks, not runtime subscription or device proof."""
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class VisibilityCaptureIntegrationContracts(unittest.TestCase):
    def test_only_two_row_callbacks_change_and_original_app_is_recoverable(self):
        app = (ROOT / 'App/Features/TimelineView.swift').read_text()
        helper = '    private func captureVisibleAfterRowChange() { session.stream.captureNotes(active ? feed.capturedIDsForVisibilityChange(visibleIDs: visibleIDs) : []) }\n'
        self.assertEqual(app.count(helper), 1)
        self.assertEqual(app.count('captureVisibleAfterRowChange()'), 3)
        restored = app.replace(helper, '').replace('visibleIDs.remove(note.id); captureVisibleAfterRowChange()', 'visibleIDs.remove(note.id); captureVisible()').replace('visibleIDs.insert(note.id)\n        captureVisibleAfterRowChange()', 'visibleIDs.insert(note.id)\n        captureVisible()')
        data = restored.encode()
        self.assertEqual(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest(), '3255655f356a6da11e8b3202a8a5df398d8f97fa')

    def test_policy_conservative_and_original_filter_retained(self):
        core = (ROOT / 'Sources/PUBOCore/TimelineState.swift').read_text()
        policy = core.split('public enum VisibilityCapturePath', 1)[1].split('private func cleaned', 1)[0]
        self.assertIn('notes.count >= 200 && (1...8).contains(visibleCount)', policy)
        self.assertIn('case .binary: return experimentalCapturedIDs(visibleIDs: visibleIDs)', policy)
        self.assertIn('case .filter: return TimelinePresentation.capturedIDs(notes.filter { visibleIDs.contains($0.id) })', policy)
        for forbidden in ['Task', 'async', 'await', 'Dictionary', 'cache', 'sleep']:
            self.assertNotIn(forbidden, policy)

    def test_native_differential_oracle_covers_policy_and_boundaries(self):
        source = (ROOT / 'Tests/PUBOCoreTests/TimelineCaptureLookupTests.swift').read_text()
        self.assertIn('XCTAssertEqual(state.capturedIDsForVisibilityChange(visibleIDs: visible), oracle', source)
        self.assertIn('[0, 20, 199, 200, 201, 2000]', source)
        self.assertIn('[0, 1, 8, 9, 2001]', source)
        self.assertIn('testSparsePolicyStillReadsReplacedRecordsAndExcludesRemovedIDs', source)
        self.assertIn('for step in 0..<400', source)
