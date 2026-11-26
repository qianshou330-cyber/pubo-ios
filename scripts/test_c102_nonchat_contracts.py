"""Static source contracts for C102 non-chat alignment fixes; not a substitute for simulator verification."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class C102NonChatSourceContracts(unittest.TestCase):
    def test_non_chat_federated_user_views_use_followee_display_handle(self):
        expectations = [
            ('App/Features/FollowRequestsView.swift', 'var body: some View', 'private func load('),
            ('App/Features/AddFriendView.swift', 'var body: some View', 'private func search('),
            ('App/Features/SocialViews.swift', 'struct SearchView: View', 'private func search('),
            ('App/Features/ProfileView.swift', 'struct ProfileView: View', 'struct FollowListView: View'),
        ]
        for rel, start, end in expectations:
            section = (ROOT / rel).read_text().split(start, 1)[1].split(end, 1)[0]
            with self.subTest(file=rel):
                self.assertIn('if let handle = FolloweeDisplayHandle.text(for: user)', section)
                self.assertIn('Text(verbatim: handle)', section)
                self.assertNotIn('Text("@" + (user["username"].string ?? ""))', section)

    def test_non_chat_retry_views_hide_stale_error_while_busy_and_guard_reentry(self):
        follow_list = (ROOT / 'App/Features/ProfileView.swift').read_text().split('struct FollowListView: View', 1)[1].split('struct EditProfileView: View', 1)[0]
        self.assertIn('if !busy, let error { ErrorBanner(message: error, retryIdentifier: "followList.retry") { Task { await load(reset: failedReset, fromRetry: true) } } }', follow_list)
        self.assertIn('private func load(reset: Bool = false, fromRetry: Bool = false) async {', follow_list)
        self.assertIn('(!fromRetry || !busy)', follow_list)

        requests = (ROOT / 'App/Features/FollowRequestsView.swift').read_text()
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load(reset: true, fromRetry: true) } } }', requests)
        self.assertIn('private func load(reset: Bool = false, fromRetry: Bool = false) async {', requests)
        self.assertIn('(!fromRetry || !busy)', requests)

        search = (ROOT / 'App/Features/SocialViews.swift').read_text().split('struct SearchView: View', 1)[1].split('struct TagNotesView: View', 1)[0]
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await search(reset: true, fromRetry: true) } } }', search)
        self.assertIn('private func search(reset: Bool, fromRetry: Bool = false) async {', search)
        self.assertIn('(!fromRetry || !busy)', search)

        guest = (ROOT / 'App/Features/GuestFeed.swift').read_text()
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }', guest)

    def test_remaining_non_chat_non_toolbar_menus_keep_compositing_boundary(self):
        notifications = (ROOT / 'App/Features/NotificationsView.swift').read_text()
        self.assertIn(
            '} label: { headerIcon("line.3.horizontal.decrease") }\n'
            '                    .compositingGroup()\n'
            '                    .foregroundStyle(filter == nil ? PUBOTheme.text : PUBOTheme.accent)',
            notifications,
        )
        self.assertIn('}.compositingGroup().accessibilityIdentifier("notifications.order")', notifications)

        compose = (ROOT / 'App/Features/ComposeView.swift').read_text()
        self.assertIn(
            '} label: { Image(systemName: visibilityIcon).frame(width: 44, height: 44) }\n'
            '                    .compositingGroup()\n'
            '                    .disabled(!editable || channelID != nil).accessibilityLabel("可见范围")',
            compose,
        )
        self.assertIn(
            '} label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }\n'
            '                    .compositingGroup()\n'
            '                    .disabled(busy).accessibilityLabel("更多").accessibilityIdentifier("compose.more")',
            compose,
        )

        guest = (ROOT / 'App/Features/GuestFeed.swift').read_text()
        self.assertIn('}.compositingGroup().accessibilityIdentifier("guest.timeline.filters")', guest)

        panels = (ROOT / 'App/Features/HomePanels.swift').read_text()
        self.assertIn('.compositingGroup().buttonStyle(.borderless).accessibilityLabel("修改公告")', panels)

        profile = (ROOT / 'App/Features/ProfileView.swift').read_text()
        self.assertIn(
            'Menu("更多操作") {\n'
            '                            Button("举报") { reporting = true }\n'
            '                            Button(user["isBlocking"].bool ? "解除屏蔽" : "屏蔽此用户", role: .destructive) { Task { await block(user) } }\n'
            '                        }.compositingGroup()',
            profile,
        )
        self.assertIn('}.compositingGroup().buttonStyle(.borderless).accessibilityIdentifier("profile.media." + field)', profile)


if __name__ == '__main__':
    unittest.main()
