import SwiftUI
import PUBOCore

struct ChatListView: View {
    @Environment(AppSession.self) private var session
    @State private var conversations: [JSONValue] = []
    @State private var error: String?
    @State private var search = false
    @State private var busy = false
    @State private var hasMore = true
    @State private var unpinnedCursor: String?
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("聊天搜索") { ChatSearchView() }
                NavigationLink("联系人") { ContactsView() }
                NavigationLink("群聊") { RoomsView() }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                ForEach(conversations, id: \.conversationID) { row in
                    let user = Record(row["user"])
                    NavigationLink { ChatView(peer: user) } label: {
                        HStack {
                            Avatar(user: user, size: 48)
                            VStack(alignment: .leading) {
                                HStack { Text(user.displayName).font(.headline); if !row["pinnedAt"].isNull { Image(systemName: "pin.fill").font(.caption) }; if row["isMuted"].bool { Image(systemName: "bell.slash").font(.caption) } }
                                Text(SendFeedback.messageSummary(row["lastMessage"])).font(.callout).lineLimit(1).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                            if let date = puboDate(row["lastMessage"]["createdAt"].string) { Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                            if row["unreadCount"].int > 0 { Text("\(row["unreadCount"].int)").font(.caption).padding(6).background(row["isMuted"].bool ? Color.gray : PUBOTheme.accent, in: Capsule()).foregroundStyle(.white) }
                            }
                        }
                    }.padding(14).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: PUBOTheme.radius)).puboListRow().swipeActions(edge: .leading) { Button(row["isMuted"].bool ? "恢复提醒" : "免打扰") { Task { await settings(user.id, "isMuted", !row["isMuted"].bool) } }.tint(.gray) }
                    .swipeActions { Button(row["pinnedAt"].isNull ? "置顶" : "取消置顶") { Task { await settings(user.id, "pinned", row["pinnedAt"].isNull) } }.tint(PUBOTheme.accent) }
                }
                if conversations.isEmpty && !busy { Text("暂无私信，点击右上角开始聊天。") }
                if busy { ProgressView() }
                if hasMore && !conversations.isEmpty { Button("加载更多会话") { Task { await load(older: true) } } }
            }.puboList().navigationTitle("私信").toolbar { Button { search = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("新私信") }
                .sheet(isPresented: $search) { UserSearchView() }
                .task { await load() }.refreshable { await load() }
                .task(id: session.streamRevision) { if session.selectedTab == 2 { try? await Task.sleep(for: .milliseconds(700)); if !Task.isCancelled { await load() } } }
        }
    }
    private func load(older: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["limit": .number(30), "pinned": .bool(false)]
            if older, let id = unpinnedCursor { fields["untilId"] = .string(id) }
            let response = try await session.call("chat/conversations", fields)
            let result = response.array
            if older { conversations += result.filter { row in !conversations.contains { $0.conversationID == row.conversationID } } }
            else {
                let pinned = try await session.call("chat/conversations", ["limit": .number(10), "pinned": .bool(true)])
                conversations = pinned.array + result.filter { row in !pinned.array.contains { $0.conversationID == row.conversationID } }
            }
            unpinnedCursor = result.last?["lastMessage"]["id"].string
            hasMore = result.count == 30; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func settings(_ peer: String, _ key: String, _ value: Bool) async {
        do { _ = try await session.call("chat/conversation-settings/update", ["userId": .string(peer), key: .bool(value)], mutation: true); await load(); await session.refreshUnread() }
        catch { self.error = error.localizedDescription }
    }
}

extension JSONValue { var conversationID: String { self["user"]["id"].string ?? "" } }

struct UserSearchView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var users: [Record] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                ForEach(users.filter { $0.id != session.user?.id }) { user in NavigationLink { ChatView(peer: user) } label: { HStack { Avatar(user: user); Text(user.displayName) } } }
                if let error { Text(error).foregroundStyle(.secondary) }
            }.puboList().searchable(text: $query, prompt: "输入本站用户名").navigationTitle("开始私信").toolbar { Button("关闭") { dismiss() } }
                .task(id: query) {
                    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { users = []; return }
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                        users = Record.list(try await session.call("users/search", ["query": .string(query), "origin": .string("local"), "limit": .number(20)])); error = nil
                    } catch is CancellationError { } catch { self.error = error.localizedDescription }
                }
        }
    }
}
