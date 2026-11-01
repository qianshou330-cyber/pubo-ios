import SwiftUI
import PUBOCore

struct AuthView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum AccountRoute: String, Identifiable {
        case login, registration
        var id: String { rawValue }
    }
    @State private var accountRoute: AccountRoute?
    private var registration: Bool { accountRoute == .registration }
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var otp = ""
    @State private var email = ""
    @State private var invitation = ""
    @State private var needOTP = false
    @State private var busy = false
    @State private var message: String?
    @State private var cooldownUntil = Date.distantPast
    @State private var webAuth = WebAuthorization()
    @State private var loginPasswordStep = false
    @State private var registrationForm = false
    @State private var agreedRules = false
    @State private var agreedPolicy = false
    @State private var agreedNotes = false
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 20

    private var needsCaptcha: Bool { ["enableHcaptcha", "enableRecaptcha", "enableMcaptcha", "enableTurnstile", "enableTestcaptcha"].contains { session.meta[$0].bool } }
    private var usernameValid: Bool { username.range(of: "^[A-Za-z0-9_]{1,20}$", options: .regularExpression) != nil }
    private var phoneValid: Bool { phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil }
    private var serverRules: [String] { session.meta["serverRules"].array.compactMap(\.string) }
    private var policies: [(String, URL)] {
        [("服务条款", session.meta["tosUrl"].string ?? session.meta["termsOfServiceUrl"].string),
         ("隐私政策", session.meta["privacyPolicyUrl"].string)].compactMap { title, raw in
            guard let raw, let url = URL(string: raw), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else { return nil }
            return (title, url)
        }
    }
    private var canAccept: Bool {
        !session.meta.isNull && (serverRules.isEmpty || agreedRules) && (policies.isEmpty || agreedPolicy) && agreedNotes
    }
    private var canRegister: Bool {
        usernameValid && phoneValid && code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil &&
        !password.isEmpty && password == confirmation &&
        (!session.meta["emailRequiredForSignup"].bool || !email.isEmpty) &&
        (!session.meta["disableRegistration"].bool || !invitation.isEmpty)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Text("PUBO").font(.system(size: titleSize, weight: .bold)).padding(.bottom, 24)
                        Text("通过帖子连接在一起的网络").font(.system(size: bodySize)).multilineTextAlignment(.center)
                        VStack(spacing: 10) {
                            Button("注册") { open(.registration) }
                                .buttonStyle(PUBOButtonStyle(kind: .registration, fullWidth: true)).accessibilityIdentifier("auth.openRegister")
                            Button("登录") { open(.login) }
                                .buttonStyle(PUBOButtonStyle(kind: .secondary, fullWidth: true)).accessibilityIdentifier("auth.openLogin")
                        }.padding(.top, 32)
                    }.padding(.horizontal, 32).padding(.top, 48).padding(.bottom, 32)
                        .frame(maxWidth: .infinity)
                        .background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: PUBOTheme.radius))
                        .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
                        .overlay(alignment: .top) { PUBOBrand(width: 220).offset(y: -42).accessibilityIdentifier("pubo.shell") }
                        .padding(.top, 42)
                    policyLinks
                }.frame(maxWidth: 430).padding(.horizontal, 16).padding(.top, 60).padding(.bottom, 32).frame(maxWidth: .infinity)
            }.puboScreen().toolbar(.hidden, for: .navigationBar)
                .sheet(item: $accountRoute) { route in accountForm(registration: route == .registration) }
        }
    }
    private func open(_ route: AccountRoute) {
        loginPasswordStep = false; registrationForm = false
        agreedRules = false; agreedPolicy = false; agreedNotes = false
        message = nil; accountRoute = route
    }

    private func accountForm(registration: Bool) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if registration {
                        if registrationForm { signupFields } else { registrationIntro }
                    } else { loginFields }
                    if let message = message ?? session.error {
                        Text(message).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("auth.error")
                    }
                    if registration && registrationForm {
                        Button { Task { await submit() } } label: {
                            HStack { if busy { ProgressView() }; Text("注册") }
                        }.buttonStyle(PUBOButtonStyle(kind: .registration, fullWidth: true))
                            .disabled(busy || !canRegister || session.meta.isNull).accessibilityIdentifier("auth.submit")
                    }
                    if !registration || registrationForm { authorizationOptions(registration: registration) }
                }.padding(24).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }.background(PUBOTheme.panel).puboScreen().scrollDismissesKeyboard(.interactively)
                .navigationTitle(registration ? "注册 PUBO" : "登录 PUBO")
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { accountRoute = nil }.disabled(busy).accessibilityIdentifier("auth.close")
                    }
                }
                .onDisappear { password = ""; confirmation = ""; otp = ""; code = ""; needOTP = false; message = nil }
        }.interactiveDismissDisabled(busy)
            .presentationDetents(registration || typeSize.isAccessibilitySize ? [.large] : [.height(560), .large])
            .presentationDragIndicator(.visible)
    }

    private var registrationIntro: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checklist").font(.system(size: 30)).foregroundStyle(PUBOTheme.accent)
                .frame(maxWidth: .infinity).padding(20).background(PUBOTheme.ownBubble, in: RoundedRectangle(cornerRadius: 12))
            Text("注册前，请先了解 PUBO").font(.title3.bold())
            if session.meta.isNull {
                ErrorBanner(message: "正在核对站点注册要求…") { Task { await session.refreshMeta() } }
            }
            if session.meta["disableRegistration"].bool { Label("本站需要邀请码才能注册。", systemImage: "key").font(.callout) }
            if !serverRules.isEmpty {
                Text("服务器规则").font(.headline)
                ForEach(Array(serverRules.enumerated()), id: \.offset) { index, rule in
                    Text("\(index + 1). \(rule)").font(.callout)
                }
                Toggle("我已阅读并同意服务器规则", isOn: $agreedRules)
            }
            if !policies.isEmpty {
                policyLinks
                Toggle("我已阅读并同意以上条款", isOn: $agreedPolicy)
            }
            Link("阅读基本注意事项", destination: URL(string: "https://misskey-hub.net/docs/for-users/onboarding/warning/")!)
            Toggle("我已阅读基本注意事项", isOn: $agreedNotes).accessibilityIdentifier("auth.agreeNotes")
            Text("本站账号与网页端通用。用户名注册后不能更改；请使用本人手机号接收验证码。")
                .font(.footnote).foregroundStyle(PUBOTheme.secondary)
            Button("继续") { registrationForm = true }
                .buttonStyle(PUBOButtonStyle(kind: .primary, fullWidth: true))
                .disabled(!canAccept).accessibilityIdentifier("auth.registrationContinue")
        }
    }

    private var signupFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("创建你的 PUBO 账号", systemImage: "person.badge.plus").font(.headline)
                .frame(maxWidth: .infinity).padding(16).background(PUBOTheme.ownBubble, in: RoundedRectangle(cornerRadius: 12))
            if session.meta["disableRegistration"].bool {
                PUBOAccountField(title: "邀请码", symbol: "key") {
                    TextField("请输入邀请码", text: $invitation).textInputAutocapitalization(.never)
                }
            }
            usernameField
            Text("仅支持 1–20 位字母、数字和下划线，注册后不能更改。").font(.footnote).foregroundStyle(PUBOTheme.secondary)
            if !username.isEmpty && !usernameValid { Text("用户名格式不正确").font(.footnote).foregroundStyle(.red) }
            if session.meta["emailRequiredForSignup"].bool {
                PUBOAccountField(title: "电子邮箱", symbol: "envelope") {
                    TextField("请输入邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
            }
            PUBOAccountField(title: "手机号码", symbol: "iphone") {
                TextField("中国大陆手机号", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityIdentifier("auth.phone")
            }
            smsFields
            PUBOPasswordField(title: "密码", value: $password, identifier: "auth.password", newPassword: true)
            PUBOPasswordField(title: "再次输入密码", value: $confirmation, identifier: "auth.confirmation", newPassword: true)
            if !confirmation.isEmpty {
                Label(password == confirmation ? "两次密码一致" : "两次密码不一致", systemImage: password == confirmation ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(password == confirmation ? PUBOTheme.accent : .red)
                    .accessibilityIdentifier("auth.passwordMatch")
            }
        }.disabled(busy)
    }
    private var smsFields: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
        return layout {
            PUBOAccountField(title: "短信验证码") {
                TextField("6 位验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).accessibilityIdentifier("auth.sms")
            }
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(ceil(cooldownUntil.timeIntervalSince(context.date))))
                Button(seconds > 0 ? "\(seconds)秒" : "获取验证码") { Task { await requestCode() } }
                    .buttonStyle(PUBOButtonStyle()).fixedSize(horizontal: true, vertical: false)
                    .disabled(seconds > 0 || busy || !phoneValid).accessibilityIdentifier("auth.requestCode")
            }
        }
    }
    private var usernameField: some View {
        PUBOAccountField(title: "用户名", suffix: "@bolubo.com", prefix: "@") {
            TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                .textContentType(.username).accessibilityIdentifier("auth.username")
        }
    }
    private var loginFields: some View {
        VStack(spacing: 24) {
            Image(systemName: "person").font(.system(size: 32))
                .foregroundStyle(PUBOTheme.secondary).frame(width: 76, height: 76)
                .background(PUBOTheme.button, in: Circle()).padding(.top, 16)
            if loginPasswordStep {
                Text("@\(username)@bolubo.com").font(.callout).multilineTextAlignment(.center)
                Button("更换账号") { loginPasswordStep = false; needOTP = false; password = ""; otp = ""; message = nil }
                    .font(.footnote).disabled(busy).accessibilityIdentifier("auth.changeAccount")
                PUBOPasswordField(title: "密码", value: $password, identifier: "auth.password")
                if needOTP {
                    PUBOAccountField(title: "两步验证代码", symbol: "lock.shield") {
                        TextField("两步验证代码", text: $otp).textContentType(.oneTimeCode).keyboardType(.numberPad).accessibilityIdentifier("auth.otp")
                    }
                }
                Button { Task { await submit() } } label: {
                    HStack { if busy { ProgressView() }; Text("登录"); Image(systemName: "arrow.right") }
                }.buttonStyle(PUBOButtonStyle(kind: .primary)).disabled(busy || password.isEmpty || (needOTP && otp.isEmpty)).accessibilityIdentifier("auth.submit")
            } else {
                usernameField
                Button { loginPasswordStep = true; message = nil } label: { Label("继续", systemImage: "arrow.right") }
                    .buttonStyle(PUBOButtonStyle(kind: .primary)).disabled(busy || !usernameValid).accessibilityIdentifier("auth.loginContinue")
            }
        }.disabled(busy)
    }
    private func authorizationOptions(registration: Bool) -> some View {
        VStack(spacing: 18) {
            HStack { Rectangle().frame(height: 1); Text("或者").font(.footnote).fixedSize(); Rectangle().frame(height: 1) }.foregroundStyle(PUBOTheme.divider)
            Button { Task { await authorize() } } label: { Label("通过本站网页安全登录", systemImage: "key") }
                .buttonStyle(PUBOButtonStyle()).disabled(busy)
            Text("通行密钥或网页安全验证，可通过本站授权窗口完成。").font(.footnote).foregroundStyle(PUBOTheme.secondary).multilineTextAlignment(.center)
            if registration && needsCaptcha {
                Text("站点启用了网页安全验证，请在本站完成注册，再返回登录。").font(.footnote)
                Link("打开本站注册", destination: Endpoint.origin)
            }
        }
    }
    private var policyLinks: some View {
        VStack(spacing: 12) {
            ForEach(policies, id: \.0) { title, url in Link(title, destination: url) }
        }.font(.footnote)
    }
    private func requestCode() async {
        busy = true; defer { busy = false }
        do {
            _ = try await session.api.call("signup/request-phone-code", body: ["phoneNumber": .string(phone)], mutation: true)
            cooldownUntil = Date().addingTimeInterval(60); message = "验证码已发送，请查收短信。"
        } catch { message = error.localizedDescription; cooldownUntil = Date().addingTimeInterval(60) }
    }
    private func submit() async {
        busy = true; message = nil; defer { busy = false }
        do {
            guard !username.isEmpty, !password.isEmpty else { throw APIError(code: "INPUT_REQUIRED", message: "请填写用户名和密码。") }
            if registration {
                guard !needsCaptcha else { throw APIError(code: "WEB_VERIFICATION", message: "请通过本站网页完成安全验证与注册。") }
                guard password == confirmation, !code.isEmpty else { throw APIError(code: "INPUT_INVALID", message: "请确认两次密码一致，并填写短信验证码。") }
                var body: [String: JSONValue] = ["username": .string(username), "password": .string(password), "phoneNumber": .string(phone), "smsCode": .string(code)]
                if !email.isEmpty { body["emailAddress"] = .string(email) }
                if !invitation.isEmpty { body["invitationCode"] = .string(invitation) }
                let response = try await session.api.call("signup", body: body, mutation: true)
                guard let token = response["token"].string else { message = "注册申请已提交，请按网站要求完成邮箱验证后登录。"; return }
                try await session.install(token: token)
            } else {
                if needsCaptcha && !needOTP { await authorize(); return }
                var body: [String: JSONValue] = ["username": .string(username), "password": .string(password)]
                if !otp.isEmpty { body["token"] = .string(otp) }
                let response = try await session.api.call("signin-flow", body: body, mutation: true)
                if let token = response["i"].string, response["finished"].bool { try await session.install(token: token) }
                else if response["next"].string == "totp" { needOTP = true; return }
                else { await authorize(); return }
            }
            password = ""; confirmation = ""; code = ""; otp = ""
        } catch { message = error.localizedDescription }
    }
    private func authorize() async {
        busy = true; defer { busy = false }
        do { let token = try await webAuth.login(api: session.api); try await session.install(token: token) }
        catch { message = error.localizedDescription }
    }
}

