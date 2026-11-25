"""Static source contracts for C101 non-chat fixes; not a substitute for simulator verification."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class C101NonChatSourceContracts(unittest.TestCase):
    def test_world_empty_initial_retry_hides_stale_error_without_debug_probes(self):
        source = (ROOT / 'App/Features/TimelineView.swift').read_text()
        heading = source.split('private var timelineHeading: some View', 1)[1].split('private var timelineRows: some View', 1)[0]
        self.assertIn('if loading && requestContext == context && feed.notes.isEmpty && error != nil && !failedOlderRequest {', heading)
        self.assertIn('ProgressView("正在加载帖子…")', heading)
        self.assertIn('.accessibilityIdentifier("timeline.initialRetryLoading")', heading)
        self.assertIn('.accessibilityIdentifier("timeline.refreshRetry")', heading)
        self.assertNotIn('C99WorldOrigin', source)

    def test_follow_list_uses_cross_site_display_handle_without_raw_username_fallback(self):
        source = (ROOT / 'App/Features/ProfileView.swift').read_text()
        follow_list = source.split('struct FollowListView: View', 1)[1].split('private func load(', 1)[0]
        self.assertIn('if let handle = FolloweeDisplayHandle.text(for: user)', follow_list)
        self.assertIn('Text(verbatim: handle).font(.caption).foregroundStyle(.secondary)', follow_list)
        self.assertNotIn('Text("@" + (user["username"].string ?? ""))', follow_list)
        self.assertNotIn('c99ChildIdentifier', source)
        self.assertNotIn('c99ChildRead', source)

    def test_non_toolbar_menus_keep_compositing_boundary_and_accessibility_labels(self):
        timeline = (ROOT / 'App/Features/TimelineView.swift').read_text()
        header = timeline.split('private var header: some View', 1)[1].split('private func day(', 1)[0]
        self.assertIn(
            '} label: { FeedIcon(name: "dots").frame(width: 44, height: 44).contentShape(Rectangle()) }\n'
            '                .compositingGroup()\n'
            '                .accessibilityLabel("世界圈筛选").accessibilityIdentifier("home.more")',
            header,
        )
        panels = (ROOT / 'App/Features/HomePanels.swift').read_text()
        chart = panels.split('struct HomeChartPanel: View', 1)[1].split('private func load()', 1)[0]
        self.assertIn(
            '.compositingGroup()\n'
            '                .accessibilityLabel("切换榜单").disabled(data["charts"].array.isEmpty)',
            chart,
        )


if __name__ == '__main__':
    unittest.main()
