import SwiftUI
import PUBOCore

/// Primary-session credentials are held only here, never in Keychain or a draft.
@Observable @MainActor final class AdminAuthorization {
    private var credential: String?
    private var owner: String?
    private var touched = Date.distantPast
    private var epoch = UUID()
    var unlocked: Bool { credential != nil && Date().timeIntervalSince(touched) < 900 }
    func clear() { epoch = UUID(); credential = nil; owner = nil; touched = .distantPast }
    func expireIfIdle() { if credential != nil && !unlocked { clear() } }
    func authorize(session: AppSession, password: String, otp: String) async throws -> Bool {
        let requestEpoch = epoch; let accountEpoch = session.generation
        guard let user = session.user, Self.canManage(user) else { throw APIError(code: "PERMISSION_DENIED", message: "当前账号没有管理权限。") }
        var fields: [String: JSONValue] = ["username": user["username"], "password": .string(password)]
        if !otp.isEmpty { fields["token"] = .string(otp) }
        let response = try await session.api.call("signin-flow", body: fields, mutation: true)
        guard requestEpoch == epoch, accountEpoch == session.generation else { throw CancellationError() }
        if response["next"].string == "totp" { return false }
        guard response["finished"].bool, let token = response["i"].string else { throw APIError(code: "SECURE_AUTH_REQUIRED", message: "此操作需要同一账号的完整会话。请先在官方网页完成所需安全验证。") }
        let confirmed = Record(try await session.api.call("i", token: token))
        guard requestEpoch == epoch, accountEpoch == session.generation else { throw CancellationError() }
        guard confirmed.id == user.id, Self.canManage(confirmed) else { throw APIError(code: "PERMISSION_DENIED", message: "账号或管理权限已变化，请重新进入。") }
        credential = token; owner = confirmed.id; touched = Date(); return true
    }
    func call(session: AppSession, path: String, fields: [String: JSONValue] = [:], mutation: Bool = false) async throws -> JSONValue {
        guard unlocked, let credential, owner == session.user?.id else { clear(); throw APIError(code: "ADMIN_EXPIRED", message: "管理授权已过期，请重新验证。") }
        let requestEpoch = epoch; let accountEpoch = session.generation
        // The server still enforces both roles and each endpoint's permission requirements.
        touched = Date()
        do {
            let result = try await session.api.call(path, body: fields, token: credential, mutation: mutation)
            guard requestEpoch == epoch, accountEpoch == session.generation else { throw CancellationError() }
            return result
        } catch {
            if ["PERMISSION_DENIED", "AUTHENTICATION_FAILED", "CREDENTIAL_REQUIRED"].contains((error as? APIError)?.code ?? "") { clear() }
            throw error
        }
    }
    static func canManage(_ user: Record) -> Bool { user["isAdmin"].bool || user["isModerator"].bool }
}

struct AdminGate<Content: View>: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder let content: () -> Content
    @State private var password = ""
    @State private var otp = ""
    @State private var needsOTP = false
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Group {
            if let user = session.user, AdminAuthorization.canManage(user) {
                if session.admin.unlocked { content() }
                else {
                    Form {
                        Text("验证当前管理员账号 @\(user["username"].string ?? "")")
                        Text("管理授权只在本次前台使用期间有效；闲置 15 分钟或进入后台后失效。").font(.footnote)
                        SecureField("管理员密码", text: $password).textContentType(.password).accessibilityIdentifier("admin.password")
                        if needsOTP { TextField("动态验证码", text: $otp).textContentType(.oneTimeCode).keyboardType(.numberPad) }
                        Button("验证并继续") { Task { await authorize() } }.disabled(busy || password.isEmpty).accessibilityIdentifier("admin.authorize")
                        if let error { ErrorBanner(message: error) }
                    }.puboForm().navigationTitle("管理授权")
                }
            } else { ContentUnavailableView("无管理权限", systemImage: "lock.shield") }
        }.task {
            #if DEBUG
            if session.isolatedBackend, let synthetic = ProcessInfo.processInfo.environment["PUBO_TEST_ADMIN_PASSWORD"] { password = synthetic }
            #endif
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                session.admin.expireIfIdle()
            }
        }.onDisappear { password = ""; otp = "" }
            .onChange(of: scenePhase) { _, phase in if phase != .active { password = ""; otp = "" } }
    }
    private func authorize() async {
        busy = true; defer { busy = false }
        do {
            let success = try await session.admin.authorize(session: session, password: password, otp: otp)
            needsOTP = !success; error = nil
            if success { password = ""; otp = "" }
        } catch { self.error = error.localizedDescription; password = ""; otp = "" }
    }
}
