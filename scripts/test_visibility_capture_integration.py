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
        # Reverse only the separately audited C101 initial-retry presentation and home.more Menu compositing boundary.
        # The unchanged full-file digest rejects all unrelated drift.
        retry_presentation = '                        if loading && requestContext == context && feed.notes.isEmpty && error != nil && !failedOlderRequest {\n                            ProgressView("正在加载帖子…")\n                                .frame(maxWidth: .infinity).padding(24)\n                                .accessibilityIdentifier("timeline.initialRetryLoading")\n                        } else {\n                            if let error, !failedOlderRequest { ErrorBanner(message: error) { Task { await load() } }.padding(12).accessibilityIdentifier("timeline.refreshRetry") }\n                            if feed.notes.isEmpty && !firstLoadFinished && error == nil { ForEach(0..<3) { _ in PostLoadingSkeleton().padding(12) } }\n                        }\n'
        prior_presentation = '                        if let error, !failedOlderRequest { ErrorBanner(message: error) { Task { await load() } }.padding(12).accessibilityIdentifier("timeline.refreshRetry") }\n                        if feed.notes.isEmpty && !firstLoadFinished && error == nil { ForEach(0..<3) { _ in PostLoadingSkeleton().padding(12) } }\n'
        self.assertEqual(restored.count(retry_presentation), 1)
        restored = restored.replace(retry_presentation, prior_presentation, 1)
        more_menu_boundary = '            } label: { FeedIcon(name: "dots").frame(width: 44, height: 44).contentShape(Rectangle()) }\n                .compositingGroup()\n                .accessibilityLabel("世界圈筛选").accessibilityIdentifier("home.more")\n'
        prior_more_menu = '            } label: { FeedIcon(name: "dots").frame(width: 44, height: 44).contentShape(Rectangle()) }\n                .accessibilityLabel("世界圈筛选").accessibilityIdentifier("home.more")\n'
        self.assertEqual(restored.count(more_menu_boundary), 1)
        restored = restored.replace(more_menu_boundary, prior_more_menu, 1)
        # Reverse only the separately audited C104 older-retry banner hide, NoteCard Menu compositing boundaries, and NoteDetailView retry state.
        c104_pairs = [
            (
                '            if !loading, let error, failedOlderRequest {\n',
                '            if let error, failedOlderRequest {\n',
            ),
            (
                '                    .compositingGroup()\n                    .accessibilityLabel("转发或引用").accessibilityIdentifier("note.renote." + rowID)\n',
                '                    .accessibilityLabel("转发或引用").accessibilityIdentifier("note.renote." + rowID)\n',
            ),
            (
                '                } label: { NoteIcon(system: "ellipsis", web: "dots", appearance: appearance, size: actionSize).frame(width: 44, height: 44).feedHitShape(appearance) }.compositingGroup().accessibilityLabel("帖子更多操作").accessibilityIdentifier("note.more." + rowID)\n',
                '                } label: { NoteIcon(system: "ellipsis", web: "dots", appearance: appearance, size: actionSize).frame(width: 44, height: 44).feedHitShape(appearance) }.accessibilityLabel("帖子更多操作").accessibilityIdentifier("note.more." + rowID)\n',
            ),
            (
                '    @State private var busy = false\n    @State private var failedOlder = false\n    var body: some View {\n        List {\n            if let note { NoteCard(note: note, detail: true) }\n            else if busy { ProgressView("正在加载帖子…") }\n            if !busy, let error { ErrorBanner(message: error) { Task { await load(older: failedOlder) } } }\n',
                '    @State private var busy = false\n    var body: some View {\n        List {\n            if let note { NoteCard(note: note, detail: true) }\n            if let error { ErrorBanner(message: error) { Task { await load() } } }\n',
            ),
            (
                '            failedOlder = false; error = nil\n        } catch { failedOlder = older; self.error = error.localizedDescription }\n',
                '            error = nil\n        } catch { self.error = error.localizedDescription }\n',
            ),
        ]
        for current_snippet, prior_snippet in c104_pairs:
            self.assertEqual(restored.count(current_snippet), 1)
            restored = restored.replace(current_snippet, prior_snippet, 1)
        # Reverse only the separately audited C105 dark-mode compose button accent softening.
        c105_compose = '                        .foregroundStyle(PUBOTheme.adaptive(0x192320, 0x101814)).background(PUBOTheme.adaptive(0x86b300, 0x7ca620), in: RoundedRectangle(cornerRadius: 12))\n'
        prior_compose = '                        .foregroundStyle(Color(red: 25/255, green: 35/255, blue: 32/255)).background(PUBOTheme.accent, in: RoundedRectangle(cornerRadius: 12))\n'
        self.assertEqual(restored.count(c105_compose), 1)
        restored = restored.replace(c105_compose, prior_compose, 1)
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
