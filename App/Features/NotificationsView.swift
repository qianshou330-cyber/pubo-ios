import SwiftUI
import PUBOCore

struct NotificationsView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [Record] = []
    @State private var loading = false
    @State private var error: String?
    @State private var hasMore = true
    var body: some View {
        NavigationStack {
            List {
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
                        if !item["isRead"].bool { Circle().fill(.green).frame(width: 7, height: 7).accessibilityLabel("未读") }
                    }
                }
                if items.isEmpty && !loading { Text("暂无通知") }
                if loading { ProgressView() }
                if hasMore && !items.isEmpty { Button("加载更多") { Task { await load(older: true) } }.disabled(loading) }
            }.navigationTitle("通知").toolbar { Button("全部已读") { Task { await markRead() } } }
                .task { await load() }.refreshable { await load() }
                .task(id: session.streamRevision) { if session.selectedTab == 1 { try? await Task.sleep(for: .milliseconds(700)); if !Task.isCancelled { await load() } } }
        }
    }
    private func title(_ record: Record) -> String {
        let names = ["follow": "关注了你", "mention": "提到了你", "reply": "回复了你", "renote": "转发了你的帖子", "quote": "引用了你的帖子", "reaction": "回应了你的帖子", "login": "账号登录提醒", "receiveFollowRequest": "请求关注你", "followRequestAccepted": "通过了关注请求"]
        return (record["user"].isNull ? "" : record.user.displayName + " ") + (names[record["type"].string ?? ""] ?? "新通知")
    }
    private func load(older: Bool = false) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            var fields: [String: JSONValue] = ["limit": .number(20)]
            if older, let id = items.last?.id { fields["untilId"] = .string(id) }
            let result = Record.list(try await session.call("i/notifications", fields))
            items = Records.merge(items, result); error = nil
            if older || items.count <= 20 { hasMore = result.count == 20 }
        } catch { self.error = error.localizedDescription }
    }
    private func markRead() async {
        do { _ = try await session.call("notifications/mark-all-as-read", mutation: true); await load() }
        catch { self.error = error.localizedDescription }
    }
}
