import SwiftUI
import PUBOCore

/// One presentation owns its secrets, cancellation and preflight results.
@MainActor @Observable final class AuthFlow {
    enum Page: String { case username, password, totp, rules, signup, forgot, emailPending }
    var page: Page
    var username = ""
    var password = ""
    var confirmation = ""
    var phone = ""
    var code = ""
    var otp = ""
    var email = ""
    var invitation = ""
    var backup = false
    var busy = false
    var captchaStep = false
    var agreedRules = false
    var agreedPolicy = false
    var agreedNotes = false
    var usernameStatus: AccountAvailability = .idle
    var emailStatus: AccountAvailability = .idle
    private var checkedUsername = ""
    private var checkedEmail = ""
    var user: Record?
    var message: String?
    var isError = false
    var cooldownUntil = Date.distantPast
    private(set) var active = true
    private var epoch = UUID()
    private var operation: Task<Void, Never>?
    private var web = WebAuthorization()
    let session: AppSession
    let addingAccount: Bool
    init(registration: Bool, session: AppSession, addingAccount: Bool) {
        page = registration ? .rules : .username; self.session = session; self.addingAccount = addingAccount
    }
    var needsCaptcha: Bool { ["enableHcaptcha", "enableRecaptcha", "enableMcaptcha", "enableTurnstile", "enableTestcaptcha"].contains { session.meta[$0].bool } }
    var emailRequired: Bool { session.meta["emailRequiredForSignup"].bool }
    var inviteRequired: Bool { session.meta["disableRegistration"].bool }
    var rules: [String] { session.meta["serverRules"].array.compactMap(\.string) }
    var policies: [(String, URL)] {
        var values: [(String, URL)] = []
        if let raw = session.meta["tosUrl"].string ?? session.meta["termsOfServiceUrl"].string,
           let url = safeMediaURL(raw) { values.append(("服务条款", url)) }
        values.append(("隐私政策", safeMediaURL(session.meta["privacyPolicyUrl"].string) ?? URL(string: "https://bolubo.com/privacy.html")!))
        return values
    }
    var canAccept: Bool { !session.meta.isNull && (rules.isEmpty || agreedRules) && agreedPolicy && agreedNotes }
    var canRegister: Bool {
        canAccept && usernameStatus.accepted && checkedUsername == username && AuthenticationInput.validUsername(username, signup: true) &&
        (!emailRequired || (emailStatus.accepted && checkedEmail == email)) && (!inviteRequired || !invitation.isEmpty) &&
        AuthenticationInput.validPhone(phone) && AuthenticationInput.validCode(code) &&
        !password.isEmpty && password == confirmation && !needsCaptcha
    }
    var canLogin: Bool {
        switch page {
        case .username: return AuthenticationInput.validUsername(username)
        case .password: return !password.isEmpty
        case .totp: return AuthenticationInput.validCode(otp, backup: backup)
        default: return false
        }
    }
    func clearSecrets() { password = ""; confirmation = ""; code = ""; otp = ""; backup = false }
    func close() { active = false; epoch = UUID(); operation?.cancel(); operation = nil; web.cancel(); clearSecrets(); busy = false; user = nil }
    func changePage(_ next: Page) {
        epoch = UUID(); operation?.cancel(); operation = nil; web.cancel(); busy = false; message = nil
        clearSecrets(); page = next
        if next == .username { user = nil; captchaStep = false }
    }
    func toggleBackup() { backup.toggle(); otp = ""; message = nil }
    private func current(_ id: UUID) -> Bool { active && epoch == id && !Task.isCancelled }
    private func run(_ action: @escaping @MainActor (UUID) async throws -> Void) {
        guard active, !busy else { return }
        busy = true; message = nil; isError = false; let id = epoch
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.current(id) { self.busy = false; self.operation = nil } }
            do { try await action(id) }
            catch { if self.current(id), !(error is CancellationError) { self.message = error.localizedDescription; self.isError = true } }
        }
    }
    func checkUsername(_ value: String) async {
        guard active, page == .signup, username == value else { return }
        guard AuthenticationInput.validUsername(value, signup: true) else { usernameStatus = value.isEmpty ? .idle : .unavailable("仅支持 1–20 位字母、数字和下划线"); return }
        usernameStatus = .checking; let id = epoch
        do {
            try await Task.sleep(for: .milliseconds(300))
            let result = try await session.api.call("username/available", body: ["username": .string(value)])
            guard current(id), page == .signup, username == value else { return }
            guard case .bool(let available) = result["available"] else { throw APIError.invalidResponse }
            usernameStatus = available ? .available : .unavailable("用户名已被使用")
            checkedUsername = value
        } catch { if current(id), page == .signup, username == value { usernameStatus = .failed } }
    }
    func checkEmail(_ value: String) async {
        guard active, page == .signup, emailRequired, email == value else { return }
        guard !value.isEmpty else { emailStatus = .idle; return }
        emailStatus = .checking; let id = epoch
        do {
            try await Task.sleep(for: .milliseconds(300))
            let result = try await session.api.call("email-address/available", body: ["emailAddress": .string(value)])
            guard current(id), page == .signup, email == value else { return }
            emailStatus = try .email(result)
            checkedEmail = value
        } catch { if current(id), page == .signup, email == value { emailStatus = .failed } }
    }
    func login() {
        guard canLogin else { return }
        run { [self] id in
            let name = username
            if page == .username {
                let profile = try? await session.api.call("users/show", body: ["username": .string(name)])
                guard current(id) else { return }
                user = profile.map(Record.init)
            }
            if page == .password && captchaStep && needsCaptcha { try await webLogin(id); return }
            var fields: [String: JSONValue] = ["username": .string(name)]
            if page != .username { fields["password"] = .string(password) }
            if page == .totp { fields["token"] = .string(otp) }
            let response = try await session.api.call("signin-flow", body: fields, mutation: true)
            guard current(id) else { return }
            switch try SigninNext(response) {
            case .password(let captcha): captchaStep = captcha; page = .password
            case .totp: otp = ""; page = .totp
            case .passkey: try await webLogin(id)
            case .finished(let token): try await install(token, id)
            }
        }
    }
    func authorize() { run { [self] id in try await webLogin(id) } }
    private func webLogin(_ id: UUID) async throws {
        let token = try await web.login(api: session.api)
        guard current(id) else { return }; try await install(token, id)
    }
    private func install(_ token: String, _ id: UUID) async throws {
        guard current(id) else { return }
        try await session.install(token: token, allowSwitch: addingAccount)
        guard current(id) else { return }; clearSecrets()
    }
    func requestCode(reset: Bool = false) {
        guard AuthenticationInput.validPhone(phone), cooldownUntil <= Date() else { return }
        let number = AuthenticationInput.phone(phone)
        run { [self] id in
            var fields: [String: JSONValue] = ["phoneNumber": .string(number)]
            if reset && !username.isEmpty { fields["username"] = .string(username) }
            _ = try await session.api.call(reset ? "request-reset-password-phone" : "signup/request-phone-code", body: fields, mutation: true)
            guard current(id) else { return }
            cooldownUntil = Date().addingTimeInterval(60); message = "验证码已发送，请查收短信。"
        }
    }
    func signup() {
        guard canRegister else { return }
        run { [self] id in
            var fields: [String: JSONValue] = ["username": .string(username), "password": .string(password), "phoneNumber": .string(AuthenticationInput.phone(phone)), "smsCode": .string(code)]
            if emailRequired { fields["emailAddress"] = .string(email) }
            if inviteRequired { fields["invitationCode"] = .string(invitation) }
            let response = try await session.api.call("signup", body: fields, mutation: true)
            guard current(id) else { return }
            if response.isNull || emailRequired { clearSecrets(); page = .emailPending; return }
            guard let token = response["token"].string, !token.isEmpty else { throw APIError.uncertain }
            try await install(token, id)
        }
    }
    func emailReset() {
        guard !username.isEmpty, !email.isEmpty, session.meta["enableEmail"].bool else { return }
        run { [self] id in
            _ = try await session.api.call("request-reset-password", body: ["username": .string(username), "email": .string(email)], mutation: true)
            guard current(id) else { return }; message = "申请已提交。若账号与邮箱匹配，请查看邮件，并在网站完成重置。"
        }
    }
    func phoneReset() {
        guard AuthenticationInput.validPhone(phone), AuthenticationInput.validCode(code), password.count >= 8, password == confirmation else { return }
        run { [self] id in
            _ = try await session.api.call("reset-password-phone", body: ["phoneNumber": .string(AuthenticationInput.phone(phone)), "smsCode": .string(code), "newPassword": .string(password)], mutation: true)
            guard current(id) else { return }; clearSecrets(); page = .username; user = nil; message = "密码已重置，请使用新密码登录。"
        }
    }
}
