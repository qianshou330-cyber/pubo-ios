import SwiftUI
import PUBOCore

/// Intended to be presented inside a NavigationStack. Never follows a user automatically.
struct AddFriendView: View {
    @Environment(AppSession.self) private var session
    @State private var username = ""
    @State private var users: [Record] = []
    @State private var busy = false
    @State private var searched = false
    @State private var offset = 0
    @State private var hasMore = false
    @State private var failedReset = true
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var visible = false
    @State private var scanner = false
    @State private var scannedUserID: String?
    @State private var showScannedProfile = false
    @FocusState private var editing: Bool
    private var searchAvailable: Bool {
        let account = session.user?["policies"]["canSearchUsers"] ?? .null
        let policy = account.isNull ? session.meta["policies"]["canSearchUsers"] : account
        return policy.isNull || policy.bool
    }
    var body: some View {
        List {
            Section {
                HStack {
                    TextField("输入用户名", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                        .focused($editing).accessibilityIdentifier("addFriend.username")
                        .onSubmit { Task { await search() } }
                    Button("搜索") { Task { await search() } }
                        .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                        .disabled(busy || !searchAvailable || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("addFriend.search")
                }
                Button { editing = false; scannedUserID = nil; scanner = true } label: { Label("扫一扫加好友", systemImage: "qrcode.viewfinder") }.accessibilityIdentifier("addFriend.scan")
            } footer: { Text("先查看用户资料，再选择关注或申请关注。扫码不会自动添加，也不会打开登录、付款等链接。") }
            if !searchAvailable { Text("当前账号没有用户搜索权限。请联系管理员核对账号权限。").accessibilityIdentifier("addFriend.permission") }
            if busy { ProgressView().accessibilityIdentifier("addFriend.loading") }
            if let error { ErrorBanner(message: error, retryIdentifier: "addFriend.retry") { Task { await search(reset: failedReset) } } }
            ForEach(users) { user in
                NavigationLink { ProfileView(userID: user.id) } label: {
                    HStack { Avatar(user: user); VStack(alignment: .leading) { Text(user.displayName); Text("@" + (user["username"].string ?? "")).font(.caption).foregroundStyle(.secondary) } }
                }.accessibilityIdentifier("addFriend.result." + user.id)
            }
            if hasMore && !busy { Button("加载更多用户") { Task { await search(reset: false) } }.accessibilityIdentifier("addFriend.more") }
            if searched && !busy && users.isEmpty && error == nil { Text("没有找到这个用户名").foregroundStyle(.secondary).accessibilityIdentifier("addFriend.empty") }
        }.puboList().navigationTitle("添加好友").scrollDismissesKeyboard(.interactively)
            .onAppear { visible = true }
            .onDisappear { visible = false; requestID = UUID(); busy = false }
            .onChange(of: username) { _, _ in requestID = UUID(); busy = false; users = []; searched = false; offset = 0; hasMore = false; error = nil }
            .onChange(of: session.generation) { _, _ in requestID = UUID(); busy = false; users = []; username = ""; searched = false; offset = 0; hasMore = false; scanner = false; scannedUserID = nil; showScannedProfile = false }
            .sheet(isPresented: $scanner, onDismiss: { showScannedProfile = scannedUserID != nil }) {
                NavigationStack {
                    FriendQRScannerView { id in scannedUserID = id; scanner = false }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { scanner = false }.accessibilityIdentifier("scanner.close") } }
                }
            }
            .navigationDestination(isPresented: $showScannedProfile) {
                if let scannedUserID { ProfileView(userID: scannedUserID) }
            }
    }
    private func search(reset: Bool = true) async {
        let text = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard visible, searchAvailable, !busy, !text.isEmpty else { return }
        guard text.count <= 100 else { error = "用户名过长，请检查输入。"; return }
        editing = false
        let ticket = UUID(), generation = session.generation
        requestID = ticket; busy = true; error = nil
        if reset { users = []; searched = false; offset = 0; hasMore = false }
        defer { if requestID == ticket { busy = false } }
        do {
            let response = try await session.call("users/search", ["query": .string(text), "limit": .number(30), "offset": .number(Double(offset))])
            try Task.checkCancellation()
            guard visible, requestID == ticket, generation == session.generation else { return }
            guard case .array = response else { throw APIError.invalidResponse }
            let rows = Record.list(response)
            guard rows.count == response.array.count, rows.allSatisfy({ !$0.id.isEmpty }), Set(rows.map(\.id)).count == rows.count else { throw APIError.invalidResponse }
            users += rows.filter { row in !users.contains(where: { $0.id == row.id }) }; offset += rows.count; hasMore = rows.count == 30; searched = true
        } catch {
            if visible && requestID == ticket && generation == session.generation && !Task.isCancelled { failedReset = reset; self.error = error.localizedDescription }
        }
    }
}
