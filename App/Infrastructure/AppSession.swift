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
    var testMode = false
    private var started = false
    let store: ProtectedStore?
    let stream = StreamClient()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024, diskPath: "PUBOPublicMedia")
        let testing: Bool
        #if DEBUG
        testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        testing = false
        #endif
        api = testing ? APIClient(transport: FixtureTransport()) : APIClient()
        store = testing ? nil : try? ProtectedStore()
        testMode = testing
        if !testing { try? PrivateFiles.clear() }
        stream.onChange = { [weak self] in self?.streamRevision += 1 }
    }

    func start() async {
        guard !started else { return }; started = true
        defer { restoring = false }
        do {
            if testMode {
                if !ProcessInfo.processInfo.arguments.contains("--logged-out") { try await install(token: "synthetic-session") }
            } else if let secret = try KeychainStore.load() {
                try await install(token: secret.token)
            }
        } catch { self.error = error.localizedDescription }
        Task { await refreshMeta() }
        Task { await refreshEmojis() }
    }
    func refreshMeta() async {
        do { meta = try await api.call("meta", body: ["detail": .bool(true)]) }
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
        if !testMode { try KeychainStore.save(LoginSecret(token: token, userID: account.id)) }
        self.token = token; user = account; error = nil
        resumeStream()
    }
    func call(_ path: String, _ fields: [String: JSONValue] = [:], mutation: Bool = false) async throws -> JSONValue {
        let epoch = generation
        let result = try await api.call(path, body: fields, token: token, mutation: mutation)
        guard epoch == generation else { throw CancellationError() }
        return result
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
        if !testMode { try KeychainStore.clear() }
        generation = UUID(); stream.stop(); token = nil; user = nil; selectedTab = 0
        InlineEmojiStore.shared.clear()
        if !testMode { do { try store?.clear(); try PrivateFiles.clear() } catch { self.error = "账号已退出，但本机缓存清理失败，请重新打开 App 后检查。"; throw error } }
        URLCache.shared.removeAllCachedResponses()
    }
    func refreshUser() async throws { user = Record(try await call("i")) }
    func resumeStream() { if let token, !testMode { stream.start(token: token) } }
}
