import SwiftUI
import PUBOCore

struct AuthRulesFields: View {
    @Bindable var flow: AuthFlow
    let close: () -> Void
    @State private var showRules = true
    @State private var showPolicies = true
    @State private var showNotes = true
    @State private var pendingAgreement: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checklist").font(.system(size: 26)).foregroundStyle(PUBOTheme.accent).frame(maxWidth: .infinity)
                .padding(16).background(PUBOTheme.ownBubble, in: RoundedRectangle(cornerRadius: 8))
            VStack(spacing: 8) {
                Text("注册前，请确认并同意以下内容。")
                Text("请好好阅读，这真的很重要。").bold()
            }.font(.subheadline).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            if flow.session.meta.isNull { ErrorBanner(message: "正在核对站点注册要求…") { Task { await flow.session.refreshMeta() } } }
            if flow.inviteRequired { Label("本站需要邀请码才能注册。", systemImage: "key").font(.callout) }
            if !flow.rules.isEmpty {
                DisclosureGroup("服务器规则", isExpanded: $showRules) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(flow.rules.enumerated()), id: \.offset) { index, rule in Text("\(index + 1). \(rule)").font(.callout) }
                        Toggle("同意", isOn: agreement("rules")).accessibilityIdentifier("auth.agreeRules")
                    }.padding(.top, 12)
                }
            }
            DisclosureGroup("服务条款与隐私政策", isExpanded: $showPolicies) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(flow.policies, id: \.0) { title, url in Link(title, destination: url) }
                    Toggle("同意", isOn: agreement("policy")).accessibilityIdentifier("auth.agreePolicy")
                }.padding(.top, 12)
            }
            DisclosureGroup("基本注意事项", isExpanded: $showNotes) {
                VStack(alignment: .leading, spacing: 12) {
                    Link("阅读基本注意事项", destination: URL(string: "https://misskey-hub.net/docs/for-users/onboarding/warning/")!)
                    Toggle("同意", isOn: agreement("notes")).accessibilityIdentifier("auth.agreeNotes")
                }.padding(.top, 12)
            }
            if !flow.canAccept { Text("必须全部勾选“同意”才能继续。").font(.footnote).frame(maxWidth: .infinity) }
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("取消", action: close).buttonStyle(PUBOButtonStyle())
                Button("继续") { flow.page = .signup }.buttonStyle(PUBOButtonStyle(kind: .primary))
                    .disabled(!flow.canAccept).accessibilityIdentifier("auth.registrationContinue")
                Spacer(minLength: 0)
            }
        }.font(.subheadline).disclosureGroupStyle(AuthRuleGroupStyle())
            .alert("你同意吗？", isPresented: Binding(get: { pendingAgreement != nil }, set: { if !$0 { pendingAgreement = nil } }), presenting: pendingAgreement) { key in
                Button("同意") { setAgreement(key, true); pendingAgreement = nil }
                Button("取消", role: .cancel) { pendingAgreement = nil }
            } message: { key in
                Text("我已仔细阅读并同意\(key == "rules" ? "服务器规则" : key == "policy" ? "服务条款及隐私政策" : "基本注意事项")。")
            }
    }
    private func agreement(_ key: String) -> Binding<Bool> {
        Binding(get: { key == "rules" ? flow.agreedRules : key == "policy" ? flow.agreedPolicy : flow.agreedNotes }, set: { if $0 { pendingAgreement = key } else { setAgreement(key, false) } })
    }
    private func setAgreement(_ key: String, _ value: Bool) {
        if key == "rules" { flow.agreedRules = value } else if key == "policy" { flow.agreedPolicy = value } else { flow.agreedNotes = value }
    }
}

private struct AuthRuleGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack { configuration.label; Spacer(); Image(systemName: configuration.isExpanded ? "chevron.up" : "chevron.down").font(.caption) }
                    .frame(minHeight: 44).padding(.horizontal, 12).background(PUBOTheme.button)
            }.buttonStyle(.plain)
            if configuration.isExpanded { configuration.content.padding(.horizontal, 14).padding(.bottom, 14) }
        }.background(PUBOTheme.background).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AuthAvailabilityLabel: View {
    let status: AccountAvailability
    let identifier: String
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            if status == .checking { ProgressView().controlSize(.small) }
            Text(status.label).font(.footnote).foregroundStyle(status.accepted ? PUBOTheme.accent : PUBOTheme.secondary)
            if status == .failed { Button("重试", action: retry).font(.footnote).frame(minHeight: 44).accessibilityIdentifier(identifier + ".retry") }
        }.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}

struct AuthSignupFields: View {
    @Bindable var flow: AuthFlow
    @State private var usernameRetry = 0
    @State private var emailRetry = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if flow.needsCaptcha {
                Label("本站已启用网页安全验证", systemImage: "shield").font(.headline)
                Text("请在本站网页完成注册，再返回 App 登录。").font(.callout)
                Link("打开本站注册", destination: Endpoint.origin).buttonStyle(PUBOButtonStyle(kind: .primary))
            } else {
                if flow.inviteRequired {
                    PUBOAccountField(title: "邀请码", symbol: "key") { TextField("请输入邀请码", text: $flow.invitation).textInputAutocapitalization(.never).accessibilityIdentifier("auth.invitation") }
                }
                VStack(alignment: .leading, spacing: 6) {
                    AuthUsernameField(flow: flow)
                    Text("仅支持 1–20 位字母、数字和下划线，注册后不能更改。").font(.footnote).foregroundStyle(PUBOTheme.secondary)
                    AuthAvailabilityLabel(status: flow.usernameStatus, identifier: "auth.usernameStatus") { usernameRetry += 1 }
                }
                if flow.emailRequired {
                    VStack(alignment: .leading, spacing: 6) {
                        AuthEmailField(flow: flow)
                        AuthAvailabilityLabel(status: flow.emailStatus, identifier: "auth.emailStatus") { emailRetry += 1 }
                    }
                }
                AuthPhoneFields(flow: flow)
                PUBOPasswordField(title: "密码", value: $flow.password, identifier: "auth.password", newPassword: true, compact: true)
                if !flow.password.isEmpty {
                    Text(AuthenticationInput.strengthLabel(flow.password)).font(.footnote).foregroundStyle(PUBOTheme.secondary).accessibilityIdentifier("auth.strength")
                }
                PUBOPasswordField(title: "再次输入密码", value: $flow.confirmation, identifier: "auth.confirmation", newPassword: true, compact: true)
                AuthPasswordMatch(flow: flow)
                Button(action: flow.signup) { HStack { if flow.busy { ProgressView() }; Text("注册") } }
                    .buttonStyle(PUBOButtonStyle(kind: .registration, fullWidth: true)).disabled(flow.busy || !flow.canRegister).accessibilityIdentifier("auth.submit")
            }
            Button("返回规则") { flow.changePage(.rules) }.font(.footnote)
        }
        .task(id: "\(flow.username)|\(usernameRetry)") { await flow.checkUsername(flow.username) }
        .task(id: "\(flow.email)|\(emailRetry)|\(flow.emailRequired)") { await flow.checkEmail(flow.email) }
        .onChange(of: flow.username) { _, _ in flow.usernameStatus = .idle }
        .onChange(of: flow.email) { _, _ in flow.emailStatus = .idle }
    }
}

struct AuthEmailField: View {
    @Bindable var flow: AuthFlow
    var body: some View {
        PUBOAccountField(title: "电子邮箱", symbol: "envelope", compact: true) {
            TextField("请输入邮箱", text: $flow.email).keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("auth.email")
        }
    }
}
struct AuthPasswordMatch: View {
    @Bindable var flow: AuthFlow
    var body: some View {
        if !flow.confirmation.isEmpty {
            Label(flow.password == flow.confirmation ? "两次密码一致" : "两次密码不一致", systemImage: flow.password == flow.confirmation ? "checkmark.circle" : "exclamationmark.circle")
                .font(.footnote).foregroundStyle(flow.password == flow.confirmation ? PUBOTheme.accent : .red).accessibilityIdentifier("auth.passwordMatch")
        }
    }
}
struct AuthPhoneFields: View {
    @Bindable var flow: AuthFlow
    var reset = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 20) {
            PUBOAccountField(title: "手机号码", symbol: "iphone", compact: true) {
                TextField("中国大陆手机号", text: $flow.phone).keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityIdentifier("auth.phone")
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
            layout {
                PUBOAccountField(title: "短信验证码", compact: true) {
                    TextField("6 位验证码", text: $flow.code).keyboardType(.numberPad).textContentType(.oneTimeCode).privacySensitive().accessibilityIdentifier("auth.sms")
                }
                SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(ceil(flow.cooldownUntil.timeIntervalSince(context.date))))
                    Button(seconds > 0 ? "\(seconds)秒" : "获取验证码") { flow.requestCode(reset: reset) }
                        .buttonStyle(PUBOButtonStyle()).fixedSize(horizontal: true, vertical: false)
                        .disabled(seconds > 0 || flow.busy || !AuthenticationInput.validPhone(flow.phone)).accessibilityIdentifier("auth.requestCode")
                }
            }
        }
    }
}
