"""Static source contracts for C105 UI layout fixes across notifications, compose, friends, me/profile, media preview, auth, and world compose button; not a substitute for simulator screenshots."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class C105UILayoutContracts(unittest.TestCase):
    def test_notifications_removes_duplicate_title_row_and_moves_actions_to_toolbar(self):
        src = (ROOT / 'App/Features/NotificationsView.swift').read_text()
        self.assertNotIn('Label("通知", systemImage: "bell")', src)
        self.assertIn('ToolbarItemGroup(placement: .topBarTrailing)', src)
        self.assertIn('headerFilter', src.split('ToolbarItemGroup(placement: .topBarTrailing)', 1)[1].split('.overlay {', 1)[0])
        self.assertIn('accessibilityIdentifier("notifications.markRead")', src.split('ToolbarItemGroup(placement: .topBarTrailing)', 1)[1].split('.overlay {', 1)[0])

    def test_compose_docks_editor_tools_above_keyboard_for_all_non_embedded_sizes(self):
        src = (ROOT / 'App/Features/ComposeView.swift').read_text()
        self.assertIn('if embedded { editorTools }', src)
        self.assertNotIn('if !typeSize.isAccessibilitySize { editorTools }', src)
        inset_block = src.split('.safeAreaInset(edge: .bottom, spacing: 0) {', 1)[1].split('.background(PUBOTheme.panel.ignoresSafeArea())', 1)[0]
        self.assertIn('if !embedded {', inset_block)
        self.assertIn('editorTools.padding(.horizontal, 16).padding(.vertical, 2)', inset_block)
        self.assertIn('Rectangle().fill(PUBOTheme.divider).frame(height: 0.5)', inset_block)

    def test_friends_and_me_use_leading_nav_titles_panel_rows_aligned_icons_and_tappable_counts(self):
        theme = (ROOT / 'App/Components/PUBOTheme.swift').read_text()
        self.assertIn('func hideSharedBackgroundIfAvailable() -> some ToolbarContent', theme)
        self.assertIn('sharedBackgroundVisibility(.hidden)', theme)
        self.assertIn('struct PUBOLeadingNavTitle: ToolbarContent', theme)

        friends = (ROOT / 'App/Features/FriendsView.swift').read_text()
        self.assertIn('Label("我的关注", systemImage: "person.badge.plus")', friends)
        self.assertIn('Label("我的关注者", systemImage: "person.2")', friends)
        self.assertEqual(friends.count('.listRowBackground(PUBOTheme.panel)'), 2)
        self.assertIn('.puboList().navigationTitle("好友")', friends)
        self.assertIn('PUBOLeadingNavTitle(title: "好友")', friends)

        profile = (ROOT / 'App/Features/ProfileView.swift').read_text()
        me = profile.split('struct MyAccountView: View', 1)[1].split('struct MyAccountSettingsView: View', 1)[0]
        self.assertNotIn('accessibilityIdentifier("me.posts")', me)
        self.assertNotIn('Label("我的动态"', me)
        self.assertNotIn('Image(systemName: "gearshape")', me)
        self.assertIn('Image(systemName: "lock.shield")', me)
        self.assertIn('.accessibilityLabel("账号与隐私设置")', me)
        self.assertIn('identifier: "me.count.posts"', me)
        self.assertIn('identifier: "me.count.following"', me)
        self.assertIn('identifier: "me.count.followers"', me)
        self.assertIn('.navigationDestination(for: AccountCountDestination.self)', me)
        self.assertEqual(me.count('.listRowBackground(PUBOTheme.panel)'), 3)
        self.assertIn('.puboList().navigationTitle("我的")', me)
        self.assertIn('PUBOLeadingNavTitle(title: "我的")', me)

    def test_role_badges_link_preview_auth_and_world_compose_button_fixes(self):
        common = (ROOT / 'App/Components/CommonViews.swift').read_text()
        badges = common.split('struct RoleBadges: View {', 1)[1].split('func safeMediaURL', 1)[0]
        self.assertIn('let roles = Record.list(user["badgeRoles"])', badges)
        self.assertIn('if !roles.isEmpty {', badges)

        profile = (ROOT / 'App/Features/ProfileView.swift').read_text()
        self.assertIn('if !Record.list(user["badgeRoles"]).isEmpty { RoleBadges(user: user) }', profile)

        media = (ROOT / 'App/Components/TimelineMedia.swift').read_text()
        preview = media.split('if appearance.isTimeline {', 1)[1].split('} else { HStack(spacing: 8)', 1)[0]
        self.assertNotIn('else { Color.clear }', preview)
        self.assertIn('if let thumb = thumbURL {', preview)
        self.assertIn('.padding(.horizontal, thumbURL == nil ? 10 : 6).padding(.vertical, 6)', preview)

        auth = (ROOT / 'App/Features/AuthView.swift').read_text()
        self.assertNotIn('Text("PUBO")', auth)
        self.assertLess(auth.index('HomeAnnouncements(refreshID: 0)'), auth.index('NavigationLink("查看全部站内公告")'))
        self.assertLess(auth.index('NavigationLink("查看全部站内公告")'), auth.index('HomeChartPanel(refreshID: 0)'))

        timeline = (ROOT / 'App/Features/TimelineView.swift').read_text()
        self.assertIn('.foregroundStyle(PUBOTheme.adaptive(0x192320, 0x101814)).background(PUBOTheme.adaptive(0x86b300, 0x7ca620), in: RoundedRectangle(cornerRadius: 12))', timeline)


if __name__ == '__main__':
    unittest.main()
