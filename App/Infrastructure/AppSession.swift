import SwiftUI
import PUBOCore

@Observable @MainActor
final class AppSession {
    let api: APIClient
    private(set) var token: String?
    private(set) var user: Record?
    private(set) var savedAccounts: [LoginSecret] = []
    private var changingAccount = false
    private(set) var generation = UUID()
    var meta: JSONValue = .null
    var emojis: [JSONValue] = []
    var recentEmojis: [String] = []
    var error: String?
    var restoring = true
    var selectedTab = 0
    var activeVoiceAttachmentID: String?
    var streamRevision = 0
    var connectionRevision = 0
    var changedChatIDs = Set<String>()
    var testMode = false
    private(set) var isolatedBackend = false
    var authorizationRequired = false
    var deletedNoteIDs = Set<String>()
    var timelinePreferences = TimelinePreferences()
    var timelineNotice: String?
    var newestTimelineNote: Record?
    var latestNoteEvent: NoteStreamEvent?
    var badges = NotificationBadges()
    var chartPreferences = KpopPreferences()
    private var unreadAttempt: UUID?
    private var started = false
    let store: ProtectedStore?
    let gifStickers: GIFStickerVault?
    let stream = StreamClient()
    let nativePush = NativePushController.shared
    let admin = AdminAuthorization()
    let security = AdminAuthorization(requiresManager: false)

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
        do {
            let parent = testing || isolated ? FileManager.default.temporaryDirectory : try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = parent.appendingPathComponent(testing || isolated ? "PUBO-GIF-UI-tests" : "PUBO-GIF", isDirectory: true)
            #if DEBUG
            if testing && ProcessInfo.processInfo.arguments.contains("--reset-stickers"), FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            #endif
            gifStickers = try GIFStickerVault(root: folder)
        } catch { gifStickers = nil }
        isolatedBackend = isolated
        testMode = testing || isolated
        nativePush.session = self
        if !testing { try? PrivateFiles.clear() }
        stream.onChange = { [weak self] in self?.streamRevision += 1 }
        stream.onConnect = { [weak self] in self?.connectionRevision += 1 }
        stream.onTimelineNote = { [weak self] note in self?.newestTimelineNote = note }
        stream.onNoteEvent = { [weak self] event in self?.latestNoteEvent = event }
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
                } else if !ProcessInfo.processInfo.arguments.contains("--logged-out") {
                    try await install(token: "synthetic-session")
                    if ProcessInfo.processInfo.arguments.contains("--multi-account-preview") { try await install(token: "synthetic-second", allowSwitch: true); try await install(token: "synthetic-session", allowSwitch: true) }
                }
            } else if let secret = try KeychainStore.load() {
                try await install(token: secret.token, expectedID: secret.userID)
            }
        } catch { self.error = error.localizedDescription }
        reloadAccounts()
        Task { await refreshMeta() }
        Task { await refreshEmojis() }
        restoreChartPreferences()
        restoreTimelinePreferences()
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
    func install(token: String, allowSwitch: Bool = false, expectedID: String? = nil) async throws {
        guard !changingAccount else { throw CancellationError() }
        changingAccount = true; defer { changingAccount = false }
        let epoch = generation
        let account = Record(try await api.call("i", token: token))
        guard !account.id.isEmpty, epoch == generation else { throw CancellationError() }
        guard expectedID == nil || expectedID == account.id else { throw APIError(code: "AUTH_ACCOUNT_MISMATCH", message: "登录信息不属于所选账号。") }
        guard allowSwitch || user == nil || user?.id == account.id else { throw APIError(code: "AUTH_ACCOUNT_MISMATCH", message: "请授权当前账号；添加其他账号请从多账号管理进入。原有草稿已保留。") }
        let secret = LoginSecret(token: token, userID: account.id, username: account["username"].string, displayName: account.displayName)
        if !testMode { try KeychainStore.save(secret) }
        if user?.id != account.id {
            generation = UUID(); stream.stop(); admin.clear(); security.clear()
            await api.cancelAll(); nativePush.logout(preservePreference: true)
            clearAccountMemory()
        }
        self.token = token; user = account; error = nil; authorizationRequired = false
        if testMode { savedAccounts.removeAll { $0.userID == account.id }; savedAccounts.append(secret) } else { reloadAccounts() }
        recentEmojis = ((try? store?.read([String].self, account: account.id, key: "recent-emojis")) ?? []).prefix(32).map { $0 }
        restoreChartPreferences()
        restoreTimelinePreferences()
        resumeStream()
        Task { await nativePush.resume() }
    }
    func call(_ path: String, _ fields: [String: JSONValue] = [:], mutation: Bool = false) async throws -> JSONValue {
        guard !changingAccount else { throw CancellationError() }
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
        guard !changingAccount else { throw CancellationError() }
        guard let token else { throw APIError(code: "CREDENTIAL_REQUIRED", message: "请先登录。") }
        let epoch = generation
        var fields = ["name": name]
        if let peer { fields["toUserId"] = peer; fields["kind"] = voice ? "voice" : "file" }
        let value = try await api.upload(path: peer == nil ? "drive/files/create" : "chat/attachments/create", data: data, filename: name, mime: mime, fields: fields, token: token)
        guard epoch == generation else { throw CancellationError() }
        return Record(value)
    }
    func logout() async throws {
        guard !changingAccount, let owner = user?.id else { return }
        changingAccount = true; defer { changingAccount = false }
        if !testMode { try KeychainStore.remove(owner) }
        generation = UUID(); stream.stop(); admin.clear(); security.clear()
        await api.cancelAll()
        nativePush.logout()
        clearAccountMemory(); savedAccounts.removeAll { $0.userID == owner }; reloadAccounts(); restoreChartPreferences()
        do { try clearLocalAccountData(owner) } catch { self.error = "账号已退出，但该账号本机数据清理失败，请重新打开 App 后检查。"; throw error }
    }
    private func clearAccountMemory() {
        token = nil; user = nil; selectedTab = 0; authorizationRequired = false; deletedNoteIDs = []; changedChatIDs = []
        badges = NotificationBadges(); unreadAttempt = nil; chartPreferences = KpopPreferences(); recentEmojis = []
        timelinePreferences = TimelinePreferences(); timelineNotice = nil; newestTimelineNote = nil; latestNoteEvent = nil
        stream.captureNotes([]); stream.showTimeline(nil)
        InlineEmojiStore.shared.clear(); try? PrivateFiles.clear(); URLCache.shared.removeAllCachedResponses()
    }
    func reloadAccounts() { if !testMode { do { savedAccounts = try KeychainStore.vault().accounts } catch { self.error = error.localizedDescription } } }
    func switchAccount(_ id: String) async throws {
        guard let secret = savedAccounts.first(where: { $0.userID == id }) else { throw APIError.invalidResponse }
        try await install(token: secret.token, allowSwitch: true, expectedID: id)
    }
    func removeSavedAccount(_ id: String) async throws {
        if user?.id == id { try await logout(); return }
        if !testMode { try KeychainStore.remove(id) }
        try clearLocalAccountData(id)
        savedAccounts.removeAll { $0.userID == id }
    }
    private func clearLocalAccountData(_ id: String) throws {
        var failure: Error?
        if !testMode { do { try store?.clear(account: id) } catch { failure = error } }
        do { try gifStickers?.clear(account: id) } catch { if failure == nil { failure = error } }
        if let failure { throw failure }
    }
    func refreshUser() async throws { user = Record(try await call("i")) }
    func rememberEmoji(_ value: String) {
        guard let owner = user?.id else { return }
        recentEmojis = Array(([value] + recentEmojis.filter { $0 != value }).prefix(32))
        try? store?.save(recentEmojis, account: owner, key: "recent-emojis")
    }
    func restoreTimelinePreferences() {
        let owner = user?.id ?? "guest"
        var value = (try? store?.read(TimelinePreferences.self, account: owner, key: "timeline-preferences-v1")) ?? TimelinePreferences()
        if let legacy = try? store?.read(String.self, account: owner, key: "selected-timeline"),
           (try? store?.read(TimelinePreferences.self, account: owner, key: "timeline-preferences-v1")) == nil { value.selected = legacy }
        let choices = user == nil ? ["local"] : HomeContent.timelines(user: user?.raw ?? .null)
        let unavailable = value.selected == "local" && !choices.contains("local")
        value.normalize(available: choices); timelinePreferences = value
        timelineNotice = unavailable ? "本地时间线暂不可用，已切换到关注。" : nil
    }
    func saveTimelinePreferences() {
        try? store?.save(timelinePreferences, account: user?.id ?? "guest", key: "timeline-preferences-v1")
    }
    func markPendingAction(_ key: String, pending: Bool) throws {
        if testMode { return }
        guard let owner = user?.id, let store else { throw APIError(code: "STORAGE_UNAVAILABLE", message: "无法保存操作状态，请暂时不要提交。") }
        try store.save(pending, account: owner, key: key)
    }
    func hasPendingAction(_ key: String) -> Bool { guard let owner = user?.id else { return false }; return (try? store?.read(Bool.self, account: owner, key: key)) ?? false }
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

