import SwiftUI
import PUBOCore

@Observable @MainActor
final class AppSession {
    let api: APIClient
    private(set) var token: String?
    private(set) var user: Record?
    private(set) var generation = UUID()
    var meta: JSONValue = .null
    var emojis: [JSONValue] = []
    var error: String?
    var restoring = true
    var selectedTab = 0
    var streamRevision = 0
    var connectionRevision = 0
    var changedChatIDs = Set<String>()
    var testMode = false
    private(set) var isolatedBackend = false
    var authorizationRequired = false
    var deletedNoteIDs = Set<String>()
    var badges = NotificationBadges()
    var chartPreferences = KpopPreferences()
    private var unreadAttempt: UUID?
    private var started = false
    let store: ProtectedStore?
    let stream = StreamClient()
    let nativePush = NativePushController.shared
    let admin = AdminAuthorization()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024, diskPath: "PUBOPublicMedia")
        let testing: Bool
        let isolated: Bool
        #if DEBUG
        testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        isolated = ProcessInfo.processInfo.arguments.contains("--isolated-backend")
        #else
        testing = false
        isolated = false
        #endif
        #if DEBUG
        api = isolated ? APIClient(transport: IsolatedTransport()) : (testing ? APIClient(transport: FixtureTransport()) : APIClient())
        #else
        api = APIClient()
        #endif
        store = testing || isolated ? nil : try? ProtectedStore()
        isolatedBackend = isolated
        testMode = testing || isolated
        nativePush.session = self
        if !testing { try? PrivateFiles.clear() }
        stream.onChange = { [weak self] in self?.streamRevision += 1 }
        stream.onConnect = { [weak self] in self?.connectionRevision += 1 }
        stream.onChatEvent = { [weak self] id in
            guard let self else { return }
            self.changedChatIDs.insert(id)
            if self.changedChatIDs.count > 2_000 { self.changedChatIDs = []; self.connectionRevision += 1 }
        }
    }

    func start() async {
        guard !started else { return }; started = true
        defer { restoring = false; Task { await nativePush.resume() } }
        do {
            if testMode {
                if isolatedBackend {
                    guard let synthetic = ProcessInfo.processInfo.environment["PUBO_ISOLATED_TOKEN"], !synthetic.isEmpty else { throw APIError.invalidResponse }
                    try await install(token: synthetic)
                } else if !ProcessInfo.processInfo.arguments.contains("--logged-out") { try await install(token: "synthetic-session") }
            } else if let secret = try KeychainStore.load() {
                try await install(token: secret.token)
            }
        } catch { self.error = error.localizedDescription }
        Task { await refreshMeta() }
        Task { await refreshEmojis() }
        restoreChartPreferences()
    }
    func refreshMeta() async {
        do { meta = try await api.call("meta", body: ["detail": .bool(true)]); await nativePush.resume() }
        catch { if meta.isNull { self.error = "站点信息加载失败，请重试。" } }
    }
    func refreshEmojis() async {
        let epoch = generation
        if let saved = try? store?.read([JSONValue].self, account: "public", key: "emojis") { emojis = saved }
        do {
            let response = try await api.call("emojis")
            guard epoch == generation else { return }
            guard case .array(let values) = response["emojis"] else { return }
            emojis = values
            try? store?.save(values, account: "public", key: "emojis")
        } catch { /* Keep known emoji data; never block account UI. */ }
    }
    func install(token: String) async throws {
        let epoch = generation
        let account = Record(try await api.call("i", token: token))
        guard !account.id.isEmpty, epoch == generation else { throw CancellationError() }
        guard user == nil || user?.id == account.id else { throw APIError(code: "AUTH_ACCOUNT_MISMATCH", message: "请授权当前账号。原账号和草稿已保留；换号请先退出登录。") }
        if !testMode { try KeychainStore.save(LoginSecret(token: token, userID: account.id)) }
        self.token = token; user = account; error = nil; authorizationRequired = false
        restoreChartPreferences()
        resumeStream()
        Task { await nativePush.resume() }
    }
    func call(_ path: String, _ fields: [String: JSONValue] = [:], mutation: Bool = false) async throws -> JSONValue {
        let epoch = generation
        let credential = token
        do {
            let result = try await api.call(path, body: fields, token: credential, mutation: mutation)
            guard epoch == generation else { throw CancellationError() }
            guard credential == token else { if mutation { throw APIError.uncertain }; throw CancellationError() }
            return result
        } catch {
            if epoch == generation && credential == token && (error as? APIError)?.code == "PERMISSION_DENIED" { authorizationRequired = true }
            throw error
        }
    }
    func upload(data: Data, name: String, mime: String, peer: String? = nil, voice: Bool = false) async throws -> Record {
        guard let token else { throw APIError(code: "CREDENTIAL_REQUIRED", message: "请先登录。") }
        let epoch = generation
        var fields = ["name": name]
        if let peer { fields["toUserId"] = peer; fields["kind"] = voice ? "voice" : "file" }
        let value = try await api.upload(path: peer == nil ? "drive/files/create" : "chat/attachments/create", data: data, filename: name, mime: mime, fields: fields, token: token)
        guard epoch == generation else { throw CancellationError() }
        return Record(value)
    }
    func logout() throws {
        admin.clear()
        if !testMode { try KeychainStore.clear() }
        nativePush.logout()
        generation = UUID(); stream.stop(); token = nil; user = nil; selectedTab = 0; authorizationRequired = false; deletedNoteIDs = []; changedChatIDs = []
        badges = NotificationBadges(); unreadAttempt = nil; chartPreferences = KpopPreferences()
        InlineEmojiStore.shared.clear()
        if !testMode { do { try store?.clear(); try PrivateFiles.clear() } catch { self.error = "账号已退出，但本机缓存清理失败，请重新打开 App 后检查。"; throw error } }
        URLCache.shared.removeAllCachedResponses()
    }
    func refreshUser() async throws { user = Record(try await call("i")) }
    func resumeStream() { if let token, !testMode || isolatedBackend { stream.start(token: token) } }
    func refreshUnread() async {
        guard user != nil, unreadAttempt == nil else { return }
        let attempt = UUID(); unreadAttempt = attempt
        defer { if unreadAttempt == attempt { unreadAttempt = nil } }
        do {
            let account = try await call("i")
            guard unreadAttempt == attempt else { return }
            badges.notification = account["hasUnreadNotification"].bool
            if account["policies"]["chatAvailability"].string != "unavailable" {
                let summary = try await call("chat/unread-summary")
                guard unreadAttempt == attempt else { return }
                try badges.applyChat(summary)
            } else { badges.chatCount = 0; badges.otherChat = false }
        } catch { /* Preserve the last authoritative badges while offline. */ }
    }
    func restoreChartPreferences() {
        chartPreferences = ((try? store?.read(KpopPreferences.self, account: user?.id ?? "guest", key: "kpop-preferences")) ?? KpopPreferences()).validated
    }
    func selectChart(_ key: String) {
        chartPreferences.selectChart(key); saveChartPreferences()
    }
    func selectChartGroup(_ id: String) {
        chartPreferences.groupID = id; chartPreferences = chartPreferences.validated; saveChartPreferences()
    }
    private func saveChartPreferences() {
        try? store?.save(chartPreferences, account: user?.id ?? "guest", key: "kpop-preferences")
    }
}
