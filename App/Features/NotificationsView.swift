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
                    Text("全部").tag("all"); Text("指定可见帖子").tag("directNotes"); Text("提及与回复").tag("mentions"); Text("表情反应").tag("reactions"); Text("关注").tag("following"); Text("系统与其他").tag("system")
                }.accessibilityIdentifier("notifications.filter")
                NavigationLink("关注申请") { FollowRequestsView() }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                ForEach(items) { item in
                    if category == "directNotes" { NoteCard(note: item) }
                    else {
                        NavigationLink { NotificationDestinationView(item: item) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                if !item["user"].isNull { Avatar(user: item.user) }
                                else { Image(systemName: icon(item)).frame(width: 38, height: 38).foregroundStyle(PUBOTheme.accent) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(title(item)).font(.subheadline.weight(.semibold))
                                    if let cw = item["note"]["cw"].string { Text(cw.isEmpty ? "内容警告 · 打开帖子查看" : cw).lineLimit(2) }
                                    else if let text = item["note"]["text"].string { Text(text).lineLimit(2) }
                                    if item["type"].string == "achievementEarned" { Text(NativeStrings.achievement(item["achievement"].string ?? "")).font(.caption) }
                                    if let name = item["invitation"]["room"]["name"].string { Text(name).font(.caption) }
                                    if let date = puboDate(item["createdAt"].string) { Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                if !item["isRead"].bool { Circle().fill(PUBOTheme.accent).frame(width: 7, height: 7).accessibilityLabel("未读") }
                            }
                        }.accessibilityIdentifier("notification." + item.id).puboCard().puboListRow()
                    }
                }
                if items.isEmpty && !loading { Text(category == "directNotes" ? "暂无指定可见帖子" : "暂无通知") }
                if loading { ProgressView() }
                if hasMore && !items.isEmpty { Button("加载更多") { Task { await load(older: true) } }.disabled(loading) }
            }.puboList().navigationTitle("通知").toolbar { if category != "directNotes" { Button("全部已读") { Task { await markRead() } } } }
                .task(id: category) { attempt = UUID(); loading = false; items = []; hasMore = true; await load() }.refreshable { await load() }
                .task(id: session.streamRevision) { if session.selectedTab == 1 { try? await Task.sleep(for: .milliseconds(700)); if !Task.isCancelled { await load() } } }
                .onDisappear { attempt = UUID(); loading = false }
        }
    }
    private func icon(_ item: Record) -> String {
        switch item["type"].string { case "chatRoomInvitationReceived": "bubble.left.and.bubble.right"; case "achievementEarned": "medal"; case "exportCompleted": "archivebox"; case "login", "createToken": "lock.shield"; default: "bell" }
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
            if category == "directNotes" { fields["visibility"] = .string("specified"); fields["following"] = .bool(false) }
            let result = Record.list(try await session.call(category == "directNotes" ? "notes/mentions" : "i/notifications", fields))
            guard attempt == request, !Task.isCancelled else { return }
            items = older ? Records.merge(items, result, limit: 2000) : result; error = nil
            hasMore = result.count == 20
            await session.refreshUnread()
        } catch { if attempt == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func markRead() async {
        do { _ = try await session.call("notifications/mark-all-as-read", mutation: true); await load(); await session.refreshUnread() }
        catch { self.error = error.localizedDescription }
    }
}
