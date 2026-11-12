import SwiftUI
import PUBOCore

struct FriendsView: View {
    @Environment(AppSession.self) private var session
    @State private var page = FollowListPage()
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var visible = false
    @State private var initializedGeneration: UUID?
    var body: some View {
        @Bindable var session = session
        NavigationStack(path: $session.friendsPath) {
            List {
                Section {
                    NavigationLink { AddFriendView() } label: { Label("搜索用户名添加好友", systemImage: "magnifyingglass") }.accessibilityIdentifier("friends.search")
                    NavigationLink { FollowRequestsView() } label: {
                        HStack {
                            Label("关注申请", systemImage: "person.badge.clock")
                            Spacer()
                            if session.pendingFollowRequestBadge != nil {
                                Text("待处理").font(.caption).foregroundStyle(PUBOTheme.accent)
                            }
                        }
                    }.accessibilityIdentifier("friends.requests")
                    NavigationLink { RoomsView() } label: { Label("已有群聊", systemImage: "person.3") }.accessibilityIdentifier("friends.rooms")
                    NavigationLink { ContactsView() } label: { Label("联系人分组", systemImage: "person.crop.rectangle.stack") }.accessibilityIdentifier("friends.contacts")
                    if let user = session.user {
                        NavigationLink("我的关注") { FollowListView(userID: user.id, followers: false) }.accessibilityIdentifier("friends.following")
                        NavigationLink("我的关注者") { FollowListView(userID: user.id, followers: true) }.accessibilityIdentifier("friends.followers")
                    }
                }
                Section {
                    ForEach(page.rows) { row in
                        let user = Record(row["followee"])
                        NavigationLink { ProfileView(userID: user.id) } label: {
                            HStack {
                                Avatar(user: user)
                                VStack(alignment: .leading) {
                                    Text(user.displayName)
                                    Text("@" + (user["username"].string ?? "")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(user["isFollowed"].bool ? "互相关注" : "已关注").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if busy { ProgressView().accessibilityIdentifier("friends.loading") }
                    if loaded && page.rows.isEmpty && error == nil { Text("还没有关注的人").foregroundStyle(.secondary).accessibilityIdentifier("friends.empty") }
                    if let error { ErrorBanner(message: error, retryIdentifier: "friends.retry") { Task { await load(reset: true) } } }
                    if loaded && page.hasMore { Button("加载更多关注") { Task { await load(reset: false) } }.disabled(busy) }
                } header: { Text("我关注的人") } footer: { Text("这里沿用关注／互相关注关系。关注申请获批不等于双方已互相关注。") }
            }.puboList().navigationTitle("好友")
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
                .toolbar { NavigationLink { AddFriendView() } label: { Label("添加好友", systemImage: "plus") }.accessibilityIdentifier("friends.add") }
                .task(id: session.generation.uuidString + String(visible)) {
                    guard visible else { return }
                    if initializedGeneration != session.generation {
                        initializedGeneration = session.generation
                        page = FollowListPage(); loaded = false; error = nil
                    }
                    if !loaded { await load(reset: true) }
                }
                .onAppear { visible = true }
                .onDisappear { visible = false; requestID = UUID(); busy = false }
                .refreshable { await load(reset: true) }
        }
    }
    private func load(reset: Bool) async {
        guard visible, let user = session.user, reset || (!busy && page.hasMore) else { return }
        let ticket = UUID(), generation = session.generation
        requestID = ticket; busy = true
        defer { if requestID == ticket { busy = false } }
        do {
            var fields: [String: JSONValue] = ["userId": .string(user.id), "limit": .number(30)]
            if !reset, let cursor = page.cursor { fields["untilId"] = .string(cursor) }
            let result = try await session.call("users/following", fields)
            try Task.checkCancellation()
            guard visible, requestID == ticket, generation == session.generation else { return }
            try page.apply(result, reset: reset, followers: false, limit: 30)
            loaded = true; error = nil
        } catch {
            if visible && requestID == ticket && generation == session.generation && !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
