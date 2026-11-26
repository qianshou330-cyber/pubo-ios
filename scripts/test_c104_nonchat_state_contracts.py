"""Static source contracts for C104 non-chat state alignment and repo-wide non-toolbar Menu boundaries; not a substitute for simulator verification."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class C104NonChatStateAndMenuContracts(unittest.TestCase):
    def test_rooms_view_never_shows_empty_state_on_error_and_hides_stale_error_while_busy(self):
        rooms = (ROOT / 'App/Features/RoomsView.swift').read_text()
        list_view = rooms.split('struct RoomsView: View', 1)[1].split('struct RoomEditor: View', 1)[0]
        self.assertIn('if !busy && loaded && rows.isEmpty && error == nil { Text("暂无群聊") }', list_view)
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load(older: failedOlder, fromRetry: true) } } }', list_view)
        self.assertIn('guard (!fromRetry || !busy), (!older || !busy) else { return }', list_view)

        members_view = rooms.split('struct RoomMembersView: View', 1)[1]
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load() } } }', members_view)
        self.assertIn('FolloweeDisplayHandle.text(for: owner)', members_view)
        self.assertIn('FolloweeDisplayHandle.text(for: user)', members_view)

    def test_contacts_messages_notifications_and_account_subpages_hide_stale_error_while_loading(self):
        contacts = (ROOT / 'App/Features/ContactsView.swift').read_text()
        self.assertIn('if !loading && loaded && groups.isEmpty && error == nil { Text("暂无联系人分组").foregroundStyle(.secondary) }', contacts)
        self.assertIn('if !loading, let error { ErrorBanner(message: error, retryIdentifier: "contacts.retry") { Task { await load(fromRetry: true) } } }', contacts)
        self.assertIn('if !loading && loaded && members.rows.isEmpty && error == nil { Text("分组暂无联系人").foregroundStyle(.secondary) }', contacts)
        self.assertIn('if !loading, let error { ErrorBanner(message: error, retryIdentifier: "contactGroup.retry") { Task { await load(reset: retryReset, fromRetry: true) } } }', contacts)
        self.assertIn('if let handle = FolloweeDisplayHandle.text(for: user)', contacts)

        chat_list = (ROOT / 'App/Features/ChatListView.swift').read_text()
        self.assertIn('if !state.busy, let issue = error ?? state.error {', chat_list)

        add_friend = (ROOT / 'App/Features/AddFriendView.swift').read_text()
        self.assertIn('if !busy, let error { ErrorBanner(message: error, retryIdentifier: "addFriend.retry")', add_friend)

        notifications = (ROOT / 'App/Features/NotificationsView.swift').read_text()
        self.assertIn('if !loading, let errorMessage { ErrorBanner(message: errorMessage)', notifications)

        social = (ROOT / 'App/Features/SocialViews.swift').read_text()
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load() } } }', social)

        profile = (ROOT / 'App/Features/ProfileView.swift').read_text()
        self.assertIn('if !busy && !loadingProfile, let error { ErrorBanner(message: error) { Task { await load() } } }', profile)

        drive = (ROOT / 'App/Features/DriveManagerView.swift').read_text()
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }', drive)

        scheduled = (ROOT / 'App/Features/ScheduledNotesView.swift').read_text()
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }', scheduled)

    def test_timeline_and_note_detail_retry_states_and_repo_wide_non_toolbar_menus(self):
        timeline = (ROOT / 'App/Features/TimelineView.swift').read_text()
        self.assertIn('if !loading, let error, failedOlderRequest {', timeline)
        self.assertIn('else if busy { ProgressView("正在加载帖子…") }', timeline)
        self.assertIn('if !busy, let error { ErrorBanner(message: error) { Task { await load(older: failedOlder) } } }', timeline)
        self.assertIn('.compositingGroup()\n                    .accessibilityLabel("转发或引用").accessibilityIdentifier("note.renote." + rowID)', timeline)
        self.assertIn('.compositingGroup().accessibilityLabel("帖子更多操作").accessibilityIdentifier("note.more." + rowID)', timeline)

        # Every non-toolbar Menu in App/ must keep a .compositingGroup() boundary to prevent iOS 26 _UIReparentingView warnings.
        menu_pattern = re.compile(r'\bMenu(?:\(| \{)')
        toolbar_menus = []
        non_toolbar_menus = []
        for swift_file in sorted((ROOT / 'App').rglob('*.swift')):
            rel = swift_file.relative_to(ROOT).as_posix()
            lines = swift_file.read_text().splitlines()
            for idx, line in enumerate(lines, start=1):
                if not menu_pattern.search(line):
                    continue
                prefix = '\n'.join(lines[max(0, idx - 4):idx])
                if '.toolbar {' in prefix or 'ToolbarItem(' in line:
                    toolbar_menus.append((rel, idx))
                    continue
                non_toolbar_menus.append((rel, idx))
                window = '\n'.join(lines[idx - 1:min(len(lines), idx + 30)])
                with self.subTest(file=rel, line=idx):
                    self.assertIn('.compositingGroup()', window)
        self.assertEqual(len(toolbar_menus), 4)
        self.assertGreaterEqual(len(non_toolbar_menus), 18)


if __name__ == '__main__':
    unittest.main()
