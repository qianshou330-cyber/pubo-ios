import SwiftUI
import PUBOCore

struct NotificationsView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [Record] = []
    @State private var loading = false
    @State private var error: String?
    @State private var hasMore = true
    @State private var category = "all"
    @State private var attempt = UUID()
    var body: some View {
        NavigationStack {
            List {
                Picker("通知分类", selection: $category) {
                    Text("全部").tag("all"); Text("提及与回复").tag("mentions"); Text("表情反应").tag("reactions"); Text("关注").tag("following"); Text("系统与其他").tag("system")
                }.accessibilityIdentifier("notifications.filter")
                NavigationLink("关注申请") { FollowRequestsView() }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                ForEach(items) { item in
                    HStack {
                        if !item["user"].isNull { Avatar(user: item.user) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(item)).font(.headline)
                            if let cw = item["note"]["cw"].string { Text(cw.isEmpty ? "内容警告 · 打开帖子查看" : cw).lineLimit(2) }
                            else if let text = item["note"]["text"].string { Text(text).lineLimit(2) }
                            if let id = item["note"]["id"].string { NavigationLink("查看帖子") { NoteDetailView(noteID: id) }.font(.caption) }
                            else if !item.user.id.isEmpty { NavigationLink("查看用户") { ProfileView(userID: item.user.id) } }
                        }
                        if !item["isRead"].bool { Circle().fill(PUBOTheme.accent).frame(width: 7, height: 7).accessibilityLabel("未读") }
                    }.puboCard().puboListRow()
                }
                if items.isEmpty && !loading { Text("暂无通知") }
                if loading { ProgressView() }
                if hasMore && !items.isEmpty { Button("加载更多") { Task { await load(older: true) } }.disabled(loading) }
            }.puboList().navigationTitle("通知").toolbar { Button("全部已读") { Task { await markRead() } } }
                .task(id: category) { attempt = UUID(); loading = false; items = []; hasMore = true; await load() }.refreshable { await load() }
                .task(id: session.streamRevision) { if session.selectedTab == 1 { try? await Task.sleep(for: .milliseconds(700)); if !Task.isCancelled { await load() } } }
                .onDisappear { attempt = UUID(); loading = false }
        }
    }
    private func title(_ record: Record) -> String {
        let names = ["follow": "关注了你", "mention": "提到了你", "reply": "回复了你", "renote": "转发了你的帖子", "quote": "引用了你的帖子", "reaction": "回应了你的帖子", "login": "账号登录提醒", "receiveFollowRequest": "请求关注你", "followRequestAccepted": "通过了关注请求", "scheduledNotePosted": "定时帖子已发布", "scheduledNotePostFailed": "定时发布失败", "pollEnded": "投票已结束", "roleAssigned": "角色已分配", "chatRoomInvitationReceived": "群聊邀请", "achievementEarned": "获得成就", "exportCompleted": "数据导出完成", "createToken": "新的账号授权", "note": "发布了新帖子"]
        return (record["user"].isNull ? "" : record.user.displayName + " ") + (names[record["type"].string ?? ""] ?? "新通知")
    }
    private func load(older: Bool = false) async {
        guard !loading else { return }; loading = true; let request = UUID(); attempt = request; defer { if attempt == request { loading = false } }
        do {
            var fields: [String: JSONValue] = ["limit": .number(20)]
            let types = ["mentions": ["mention", "reply", "quote"], "reactions": ["reaction", "renote"], "following": ["follow", "receiveFollowRequest", "followRequestAccepted"]]
            if let included = types[category] { fields["includeTypes"] = .strings(included) }
            else if category == "system" { fields["excludeTypes"] = .strings(types.values.flatMap { $0 }) }
            if older, let id = items.last?.id { fields["untilId"] = .string(id) }
            let result = Record.list(try await session.call("i/notifications", fields))
            guard attempt == request, !Task.isCancelled else { return }
            items = Records.merge(items, result); error = nil
            if older || items.count <= 20 { hasMore = result.count == 20 }
            await session.refreshUnread()
        } catch { if attempt == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func markRead() async {
        do { _ = try await session.call("notifications/mark-all-as-read", mutation: true); await load(); await session.refreshUnread() }
        catch { self.error = error.localizedDescription }
    }
}
