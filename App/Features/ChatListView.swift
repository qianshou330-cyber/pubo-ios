import SwiftUI
import PUBOCore

struct ChatListView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = ChatHomeState()
    @State private var section = "home"
    @State private var active = false
    @State private var search = false
    @State private var creating = false
    @State private var settingBusy = false
    @State private var error: String?
    private var chatProblem: String? { ChatEligibility.problem(account: session.user) }
    private var visible: Bool { active && session.selectedTab == 2 && scenePhase == .active && section == "home" }
    private let tabs = [ChatTab(id: "home", title: "首页", icon: "house"), ChatTab(id: "invited", title: "邀请", icon: "envelope"), ChatTab(id: "joining", title: "已加入的群聊", icon: "person.2"), ChatTab(id: "owned", title: "已创建的群聊", icon: "person.2.badge.gearshape")]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatTabs(selection: $section, items: tabs, prefix: "chat.home.")
                if section == "home" { home }
                else { RoomsView(fixedSection: section, embedded: true).id(section) }
            }.puboScreen().navigationTitle("私信")
                .sheet(isPresented: $search) { UserSearchView() }
                .sheet(isPresented: $creating, onDismiss: { section = "owned" }) { RoomEditor() }
                .onAppear { active = true }.onDisappear { active = false; state.invalidate() }
                .task(id: "\(visible)-\(session.generation)") {
                    guard !Task.isCancelled else { return }
                    // A cancelled visibility task can still be unwinding its reads.
                    // Give the new visible task its own epoch before checking busy.
                    state.invalidate()
                    guard visible else { return }
                    repeat {
                        await state.load(session)
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    } while visible && !Task.isCancelled
                }
                .task(id: session.streamRevision) {
                    guard visible else { return }
                    do { try await Task.sleep(for: .milliseconds(500)); await state.load(session) } catch { }
                }
                .onChange(of: session.generation) { _, _ in state.clear(); section = "home"; search = false; creating = false }
        }
    }
    private var home: some View {
        List {
            VStack(alignment: .leading, spacing: 16) {
                if let chatProblem { Text(chatProblem).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("chat.availability") }
                Menu {
                    Button("一对一聊天") { search = true }
                    Button("创建群聊") { creating = true }
                } label: { Label("开始聊天", systemImage: "plus").frame(minHeight: 44).padding(.horizontal, 22).background(PUBOTheme.accent, in: Capsule()).foregroundStyle(PUBOTheme.background) }
                    .frame(maxWidth: .infinity).disabled(chatProblem != nil).accessibilityIdentifier("chat.start")
                NavigationLink { ContactsView() } label: { Label("联系人", systemImage: "person.2").frame(minHeight: 44) }
            }.puboListRow()
            ChatSearchView(embedded: true)
            Section {
                if let issue = error ?? state.error { ErrorBanner(message: issue) { Task { await state.load(session) } }.puboListRow() }
                ForEach(state.rows) { row in
                    if row.id == state.rows.first?.id && row.pinnedAt != nil { Text("置顶").font(.caption).foregroundStyle(.secondary).puboListRow() }
                    if row.pinnedAt == nil && state.rows.contains(where: { $0.pinnedAt != nil }) && row.id == state.rows.first(where: { $0.pinnedAt == nil })?.id { Text("最近会话").font(.caption).foregroundStyle(.secondary).puboListRow() }
                    HStack(spacing: 0) {
                        NavigationLink { destination(row) } label: { conversation(row) }.buttonStyle(.plain)
                            .accessibilityIdentifier("conversation." + row.id)
                        if row.kind == .user {
                            Menu {
                                Button(row.pinnedAt == nil ? "置顶" : "取消置顶") { Task { await settings(row, "pinned", row.pinnedAt == nil) } }
                                Button(row.muted ? "恢复提醒" : "免打扰") { Task { await settings(row, "isMuted", !row.muted) } }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.disabled(settingBusy).accessibilityLabel(row.target.displayName + "会话设置")
                        }
                    }.padding(12).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 12)).puboListRow()
                        .swipeActions(edge: .leading) { if row.kind == .user { Button(row.muted ? "恢复提醒" : "免打扰") { Task { await settings(row, "isMuted", !row.muted) } }.tint(.gray) } }
                        .swipeActions { if row.kind == .user { Button(row.pinnedAt == nil ? "置顶" : "取消置顶") { Task { await settings(row, "pinned", row.pinnedAt == nil) } }.tint(PUBOTheme.accent) } }
                }
                if state.rows.isEmpty && !state.busy { Text("暂无最近会话").foregroundStyle(.secondary).puboListRow() }
                if state.busy { ProgressView().puboListRow() }
                if state.hasMore && !state.rows.isEmpty { Button("加载更多会话") { Task { await state.load(session, older: true) } }.disabled(state.busy).frame(minHeight: 44).puboListRow() }
            } header: { Text("最近会话").font(.subheadline) }
        }.puboList().refreshable { await state.load(session) }
    }
    @ViewBuilder private func destination(_ row: ChatConversation) -> some View {
        if row.kind == .room { RoomChatView(roomID: row.target.id) } else { ChatView(peer: row.target) }
    }
    private func conversation(_ row: ChatConversation) -> some View {
        HStack(spacing: 12) {
            Avatar(user: row.kind == .user ? row.target : Record(row.message["fromUser"]), size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if row.kind == .room { Image(systemName: "person.2").font(.caption) }
                    Text(row.kind == .room ? (row.target["name"].string ?? "群聊") : row.target.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if row.pinnedAt != nil { Image(systemName: "pin.fill").font(.caption2) }
                    if row.muted { Image(systemName: "bell.slash").font(.caption2) }
                    Spacer(minLength: 0)
                    if let date = puboDate(row.message["createdAt"].string) { ChatRelativeTime(date: date).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }
                HStack {
                    Text((row.message["fromUserId"].string == session.user?.id ? "你：" : "") + SendFeedback.messageSummary(row.message.raw)).font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let badge = row.badge { Text(badge).font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).background(row.muted ? Color.gray : PUBOTheme.accent, in: Capsule()).foregroundStyle(.white) }
                    else if row.legacyUnread { Circle().fill(row.muted ? .gray : PUBOTheme.accent).frame(width: 8, height: 8).accessibilityLabel("有未读消息") }
                }
            }
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
    private func settings(_ row: ChatConversation, _ key: String, _ value: Bool) async {
        guard !settingBusy, row.kind == .user else { return }; settingBusy = true; defer { settingBusy = false }
        do { _ = try await session.call("chat/conversation-settings/update", ["userId": .string(row.target.id), key: .bool(value)], mutation: true); await state.load(session); await session.refreshUnread(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

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
