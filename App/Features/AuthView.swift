import SwiftUI
import PUBOCore

struct AuthView: View {
    @Environment(AppSession.self) private var session
    @State private var registration = false
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

    private var needsCaptcha: Bool { ["enableHcaptcha", "enableRecaptcha", "enableMcaptcha", "enableTurnstile", "enableTestcaptcha"].contains { session.meta[$0].bool } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image("Brand").resizable().scaledToFit().frame(width: 200, height: 72).padding(12).background(Color(red: 11/255, green: 20/255, blue: 18/255), in: RoundedRectangle(cornerRadius: 18)).accessibilityLabel("PUBO").accessibilityIdentifier("pubo.shell")
                        Text("通过帖子连接在一起").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 22)
                    Picker("账号", selection: $registration) { Text("登录").tag(false); Text("注册").tag(true) }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear)
                if session.meta.isNull && registration {
                    Section { Button("重新读取注册设置") { Task { await session.refreshMeta() } }; Text("正在核对站点注册要求…") }
                }
                Section(registration ? "创建 PUBO 账号" : "已有账号") {
                    TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username).accessibilityIdentifier("auth.username")
                    SecureField("密码", text: $password).textContentType(registration ? .newPassword : .password).accessibilityIdentifier("auth.password")
                    if registration {
                        SecureField("再次输入密码", text: $confirmation).textContentType(.newPassword)
                        TextField("手机号码", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        HStack {
                            TextField("短信验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                                let seconds = max(0, Int(ceil(cooldownUntil.timeIntervalSince(context.date))))
                                Button(seconds > 0 ? "\(seconds)秒" : "获取验证码") { Task { await requestCode() } }.disabled(seconds > 0 || busy || phone.count != 11)
                            }
                        }
                        if session.meta["emailRequiredForSignup"].bool { TextField("电子邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never) }
                        if session.meta["disableRegistration"].bool { TextField("邀请码", text: $invitation).textInputAutocapitalization(.never) }
                    }
                    if needOTP { TextField("两步验证代码", text: $otp).textContentType(.oneTimeCode).keyboardType(.numberPad) }
                }
                if let message = message ?? session.error { Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("auth.error") } }
                Section {
                    Button { Task { await submit() } } label: { HStack { Spacer(); if busy { ProgressView() }; Text(registration ? "注册" : "登录"); Spacer() } }
                        .buttonStyle(.borderedProminent).tint(Color(red: 45/255, green: 193/255, blue: 0)).disabled(busy || (registration && session.meta.isNull)).accessibilityIdentifier("auth.submit")
                    Button("通过本站网页安全授权") { Task { await authorize() } }.disabled(busy)
                    if registration && needsCaptcha { Text("站点启用了网页安全验证，请先在本站完成注册，再返回授权登录。").font(.footnote); Link("打开本站注册", destination: Endpoint.origin) }
                }
                Section {
                    ForEach([("privacyPolicyUrl", "隐私政策"), ("termsOfServiceUrl", "服务条款")], id: \.0) { key, title in
                        if let value = session.meta[key].string, let url = URL(string: value), url.scheme == "https" { Link(title, destination: url) }
                    }
                }
            }.navigationTitle("欢迎来到 PUBO")
                .onChange(of: registration) { _, _ in message = nil; password = ""; confirmation = ""; needOTP = false; otp = "" }
                .onDisappear { password = ""; confirmation = ""; otp = ""; code = "" }
        }
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
