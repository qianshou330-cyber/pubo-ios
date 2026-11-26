import Foundation
import SwiftUI
import PUBOCore

private enum MessagesHomePage: Hashable { case search }

enum MessagesHomePalette {
    static let canvas = PUBOTheme.adaptive(0xffffff, 0x0c1210)
    static let primary = PUBOTheme.adaptive(0x141414, 0xeff3ee)
    static let secondary = PUBOTheme.adaptive(0x666b68, 0xaebbb4)
    static let field = PUBOTheme.adaptive(0xf1f2f3, 0x202a26)
    static let accent = PUBOTheme.adaptive(0x477019, 0xb3d084)
    static let badge = PUBOTheme.adaptive(0x477019, 0x496d2a)
    static let addBackground = PUBOTheme.adaptive(0xe6edd9, 0x293b25)
    static let rule = PUBOTheme.adaptive(0xe4e6e4, 0x334039)
}

struct ChatListView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 32
    private let sideInset: CGFloat = 16
    private let avatarSize: CGFloat = 50
    private let rowSpacing: CGFloat = 12
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = ChatHomeState()
    @State private var active = false
    @State private var search = false
    @State private var scanner = false
    @State private var scannedUserID: String?
    @State private var showScannedProfile = false
    @State private var settingBusy = false
    @State private var error: String?
    private var chatProblem: String? { ChatEligibility.problem(account: session.user) }
    private var visible: Bool { active && session.selectedTab == .messages && scenePhase == .active }
    var body: some View {
        @Bindable var session = session
        NavigationStack(path: $session.messagesPath) {
            home
                .navigationTitle("消息")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MessagesHomePage.self) { _ in
                    ChatSearchView(homeReadOnly: true)
                }
                .sheet(isPresented: $search) {
                    NavigationStack {
                        AddFriendView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { search = false }.accessibilityIdentifier("addFriend.close") } }
                    }
                }
                .sheet(isPresented: $scanner, onDismiss: { showScannedProfile = scannedUserID != nil }) {
                    NavigationStack {
                        FriendQRScannerView { id in scannedUserID = id; scanner = false }
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { scanner = false }.accessibilityIdentifier("scanner.close") } }
                    }
                }
                .navigationDestination(isPresented: $showScannedProfile) { if let scannedUserID { ProfileView(userID: scannedUserID) } }
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
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
                .onChange(of: session.generation) { _, _ in state.clear(); search = false; scanner = false; scannedUserID = nil; showScannedProfile = false }
        }
    }
    private var home: some View {
        VStack(spacing: 0) {
            homeHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let chatProblem {
                        Text(chatProblem).font(.caption).foregroundStyle(MessagesHomePalette.secondary)
                            .accessibilityIdentifier("chat.availability")
                            .padding(.vertical, 10)
                    }
                    if !state.busy, let issue = error ?? state.error {
                        ErrorBanner(message: issue, retryIdentifier: "messages.retry") {
                            error = nil
                            Task { await state.load(session) }
                        }.padding(.vertical, 10)
                    }
                    ForEach(state.rows) { row in
                        conversationLink(row)
                            .overlay(alignment: .bottomLeading) {
                                if row.id != state.rows.last?.id {
                                    MessagesHomePalette.rule.frame(height: 0.5)
                                        .padding(.leading, avatarSize + rowSpacing)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                    }
                    if state.rows.isEmpty && !state.busy && state.error == nil && error == nil {
                        Text("暂无最近会话").font(.subheadline).foregroundStyle(MessagesHomePalette.secondary)
                            .accessibilityIdentifier("messages.empty").padding(.top, 24)
                    }
                    if state.busy {
                        ProgressView().accessibilityIdentifier("messages.loading").padding(.vertical, 12)
                    }
                    if state.hasMore && !state.rows.isEmpty {
                        Button("加载更多会话") { Task { await state.load(session, older: true) } }
                            .disabled(state.busy).frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, sideInset)
                // Reserve one tab-bar body at the scroll tail; the shell owns the home-indicator inset.
                .padding(.bottom, 8 + BottomTabBar.minimumContentHeight)
            }
            .accessibilityIdentifier("messages.conversations")
            .refreshable { await state.load(session) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MessagesHomePalette.canvas.ignoresSafeArea())
        .tint(MessagesHomePalette.accent)
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("消息")
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(MessagesHomePalette.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("messages.title")
                Spacer(minLength: 8)
                Menu {
                    Button { scannedUserID = nil; scanner = true } label: {
                        Label("扫一扫", systemImage: "qrcode.viewfinder")
                    }.accessibilityIdentifier("messages.scan")
                    Button { search = true } label: {
                        Label("输入用户名加好友", systemImage: "person.badge.plus")
                    }.accessibilityIdentifier("messages.addUsername")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MessagesHomePalette.accent)
                        .frame(width: 34, height: 34)
                        .background(MessagesHomePalette.addBackground, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .compositingGroup()
                .buttonStyle(.plain)
                .accessibilityLabel("添加好友")
                .accessibilityIdentifier("messages.add")
            }
            NavigationLink(value: MessagesHomePage.search) {
                Label("搜索聊天记录", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(MessagesHomePalette.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .background(MessagesHomePalette.field, in: RoundedRectangle(cornerRadius: 11))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("messages.search.open")
        }
        .padding(.horizontal, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    @ViewBuilder private func conversationLink(_ row: ChatConversation) -> some View {
        let account = conversationAccount(row)
        let link = NavigationLink { destination(row) } label: {
            conversation(row)
                #if DEBUG
                .onAppear { ConversationDiagnostics.shared.record(.rowAppeared) }
                .onDisappear { ConversationDiagnostics.shared.record(.rowDisappeared) }
                #endif
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation." + row.id)
        if row.kind == .user {
            link.accessibilityValue(Text(verbatim: account ?? ""))
                .contextMenu {
                    Button(pinTitle(row)) { Task { await settings(row, "pinned", row.pinnedAt == nil) } }
                        .disabled(settingBusy)
                    Button(muteTitle(row)) { Task { await settings(row, "isMuted", !row.muted) } }
                        .disabled(settingBusy)
                }
                .accessibilityAction(named: Text(pinTitle(row))) { Task { await settings(row, "pinned", row.pinnedAt == nil) } }
                .accessibilityAction(named: Text(muteTitle(row))) { Task { await settings(row, "isMuted", !row.muted) } }
        } else {
            link
        }
    }

    private func pinTitle(_ row: ChatConversation) -> String { row.pinnedAt == nil ? "置顶" : "取消置顶" }
    private func muteTitle(_ row: ChatConversation) -> String { row.muted ? "恢复提醒" : "免打扰" }

    @ViewBuilder private func destination(_ row: ChatConversation) -> some View {
        if row.kind == .room {
            RoomChatView(roomID: row.target.id)
                #if DEBUG
                .onAppear { ConversationDiagnostics.shared.record(.destinationAppeared) }
                .onDisappear { ConversationDiagnostics.shared.record(.destinationDisappeared) }
                #endif
        } else {
            ChatView(peer: row.target)
                #if DEBUG
                .onAppear { ConversationDiagnostics.shared.record(.destinationAppeared) }
                .onDisappear { ConversationDiagnostics.shared.record(.destinationDisappeared) }
                #endif
        }
    }
    private func conversation(_ row: ChatConversation) -> some View {
        HStack(spacing: rowSpacing) {
            MessagesHomeAvatar(row: row, size: avatarSize)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(verbatim: row.kind == .room ? (row.target["name"].string ?? "群聊") : row.target.displayName)
                        .font(.headline.weight(.semibold)).foregroundStyle(MessagesHomePalette.primary)
                        .lineLimit(1).truncationMode(.tail)
                        .accessibilityIdentifier("messages.name." + row.id)
                    if row.pinnedAt != nil { Image(systemName: "pin.fill").font(.caption2).accessibilityLabel("已置顶") }
                    if row.muted { Image(systemName: "bell.slash").font(.caption2).accessibilityLabel("免打扰") }
                }
                Text(verbatim: (row.message["fromUserId"].string == session.user?.id ? "你：" : "") + SendFeedback.messageSummary(row.message.raw))
                    .font(.subheadline).foregroundStyle(MessagesHomePalette.secondary)
                    .lineLimit(1).truncationMode(.tail)
                    .accessibilityIdentifier("messages.preview." + row.id)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                if let date = puboDate(row.message["createdAt"].string) {
                    ChatRelativeTime(date: date)
                        .font(.caption).foregroundStyle(MessagesHomePalette.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("messages.time." + row.id)
                }
                ZStack(alignment: .trailing) {
                    Color.clear.frame(width: 1, height: 20).accessibilityHidden(true)
                    if let badge = row.badge {
                        Text(verbatim: badge)
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(row.muted ? Color.gray : MessagesHomePalette.badge, in: Capsule())
                            .accessibilityIdentifier("messages.unread." + row.id)
                    } else if row.legacyUnread {
                        Circle().fill(row.muted ? Color.gray : MessagesHomePalette.accent)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel("有未读消息")
                            .accessibilityIdentifier("messages.unread." + row.id)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .foregroundStyle(MessagesHomePalette.secondary)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 80)
        .contentShape(Rectangle())
    }
    // This is a supplemental display token, not an account lookup or canonicalizer.
    private func conversationAccount(_ row: ChatConversation) -> String? {
        guard row.kind == .user, let rawUsername = row.target["username"].string,
              rawUsername.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        let host: String
        switch row.target["host"] {
        case .null:
            host = ""
        case .string(let rawHost):
            guard rawHost.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
            host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return nil
        }
        if host.isEmpty {
            guard username.range(of: #"\A[A-Za-z0-9_]{1,20}\z"#, options: .regularExpression) != nil else { return nil }
            return "@\(username)"
        }
        // A malformed present host must not make a remote account look local.
        let label = #"\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z"#
        guard username.utf8.count <= 128,
              username.range(of: #"\A[A-Za-z0-9_]+(?:[.-][A-Za-z0-9_]+)*\z"#, options: .regularExpression) != nil,
              host.utf8.count <= 253,
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  String($0).range(of: label, options: .regularExpression) != nil
              }) else { return nil }
        return "@\(username)@\(host)"
    }

    private func settings(_ row: ChatConversation, _ key: String, _ value: Bool) async {
        guard !settingBusy, row.kind == .user else { return }; settingBusy = true; defer { settingBusy = false }
        do { _ = try await session.call("chat/conversation-settings/update", ["userId": .string(row.target.id), key: .bool(value)], mutation: true); await state.load(session); await session.refreshUnread(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct MessagesHomeAvatar: View {
    let row: ChatConversation
    let size: CGFloat

    private var url: URL? {
        safeMediaURL(row.target["avatarUrl"].string)
            ?? (row.kind == .room ? safeMediaURL(row.target["iconUrl"].string) : nil)
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { fallback }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            (row.kind == .room ? MessagesHomePalette.badge : MessagesHomePalette.addBackground)
            Image(systemName: row.kind == .room ? "waveform" : "person.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(row.kind == .room ? Color(red: 0.78, green: 0.91, blue: 0.43) : MessagesHomePalette.accent)
        }
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

