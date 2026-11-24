"""Static integration scope checks, not runtime subscription or device proof."""
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class VisibilityCaptureIntegrationContracts(unittest.TestCase):
    def test_only_two_row_callbacks_change_and_original_app_is_recoverable(self):
        app = (ROOT / 'App/Features/TimelineView.swift').read_text()
        # Ignore only these two exact, launch-gated DEBUG origins. Any other drift still fails.
        diagnostic = 'if let error, !failedOlderRequest { ErrorBanner(message: error) { Task {\n                                #if DEBUG\n                                if C99WorldOrigin.enabled {\n                                    await C99WorldOrigin.$source.withValue(.retry) { await load() }\n                                    return\n                                }\n                                #endif\n                                await load()\n                            } }.padding(12).accessibilityIdentifier("timeline.refreshRetry") }'
        self.assertEqual(app.count(diagnostic), 1)
        app = app.replace(diagnostic, 'if let error, !failedOlderRequest { ErrorBanner(message: error) { Task { await load() } }.padding(12).accessibilityIdentifier("timeline.refreshRetry") }', 1)
        diagnostic = '                    #if DEBUG\n                    if C99WorldOrigin.enabled {\n                        await C99WorldOrigin.$source.withValue(.initial) { await load() }\n                        return\n                    }\n                    #endif\n                    await load()\n    }\n    private func appeared'
        self.assertEqual(app.count(diagnostic), 1)
        app = app.replace(diagnostic, '                    await load()\n    }\n    private func appeared', 1)
        helper = '    private func captureVisibleAfterRowChange() { session.stream.captureNotes(active ? feed.capturedIDsForVisibilityChange(visibleIDs: visibleIDs) : []) }\n'
        self.assertEqual(app.count(helper), 1)
        self.assertEqual(app.count('captureVisibleAfterRowChange()'), 3)
        restored = app.replace(helper, '').replace('visibleIDs.remove(note.id); captureVisibleAfterRowChange()', 'visibleIDs.remove(note.id); captureVisible()').replace('visibleIDs.insert(note.id)\n        captureVisibleAfterRowChange()', 'visibleIDs.insert(note.id)\n        captureVisible()')
        # Reverse only the separately audited initial-retry presentation.
        # The unchanged full-file digest rejects all unrelated drift.
        retry_presentation = '                        if loading && requestContext == context && feed.notes.isEmpty && error != nil && !failedOlderRequest {\n                            ProgressView("正在加载帖子…")\n                                .frame(maxWidth: .infinity).padding(24)\n                                .accessibilityIdentifier("timeline.initialRetryLoading")\n                        } else {\n                            if let error, !failedOlderRequest { ErrorBanner(message: error) { Task { await load() } }.padding(12).accessibilityIdentifier("timeline.refreshRetry") }\n                            if feed.notes.isEmpty && !firstLoadFinished && error == nil { ForEach(0..<3) { _ in PostLoadingSkeleton().padding(12) } }\n                        }\n'
        prior_presentation = '                        if let error, !failedOlderRequest { ErrorBanner(message: error) { Task { await load() } }.padding(12).accessibilityIdentifier("timeline.refreshRetry") }\n                        if feed.notes.isEmpty && !firstLoadFinished && error == nil { ForEach(0..<3) { _ in PostLoadingSkeleton().padding(12) } }\n'
        self.assertEqual(restored.count(retry_presentation), 1)
        restored = restored.replace(retry_presentation, prior_presentation, 1)
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
