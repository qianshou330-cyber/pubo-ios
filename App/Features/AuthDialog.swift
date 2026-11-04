import SwiftUI
import PUBOCore

struct AuthDialog: View {
    @Bindable var flow: AuthFlow
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboardVisible = false
    @ScaledMetric(relativeTo: .headline) private var headerSize: CGFloat = 14
    private var registration: Bool { [.rules, .signup, .emailPending].contains(flow.page) }
    private var title: String { registration ? "注册 PUBO" : flow.page == .forgot ? "重置密码" : "登录 PUBO" }
    var body: some View {
        GeometryReader { area in
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: close).accessibilityHidden(true)
                VStack(spacing: 0) {
                    HStack {
                        Text(title).font(.system(size: headerSize, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("auth.title")
                        if keyboardVisible {
                            Button { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel("收起键盘").accessibilityIdentifier("auth.hideKeyboard")
                        }
                        Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("关闭").accessibilityIdentifier("auth.close")
                    }.padding(.leading, 20).padding(.trailing, 4).frame(minHeight: 50)
                    Divider().overlay(PUBOTheme.divider)
                    ScrollView {
                        VStack(spacing: 20) {
                            step.id(flow.page).transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 35)), removal: .opacity.combined(with: .offset(x: -35))))
                            if let message = flow.message {
                                Text(message).font(.footnote).foregroundStyle(flow.isError ? Color.red : PUBOTheme.text)
                                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("auth.error")
                            }
                        }.padding(registration || flow.page == .forgot ? 28 : 32).frame(maxWidth: .infinity)
                    }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("auth.content")
                }.frame(width: min(registration ? 500 : 400, max(0, area.size.width - 24)), height: min(registration || flow.page == .forgot ? 600 : 450, max(0, area.size.height - 24)))
                    .background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: PUBOTheme.radius))
                    .clipShape(RoundedRectangle(cornerRadius: PUBOTheme.radius))
                    .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal).accessibilityIdentifier("auth.dialog")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.foregroundStyle(PUBOTheme.text).tint(PUBOTheme.accent)
            .animation(.timingCurve(0, 0, 0.35, 1, duration: 0.3), value: flow.page)
            .onDisappear { flow.close() }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }
    @ViewBuilder private var step: some View {
        switch flow.page {
        case .username, .password, .totp: AuthLoginFields(flow: flow)
        case .rules: AuthRulesFields(flow: flow, close: close)
        case .signup: AuthSignupFields(flow: flow)
        case .forgot: AuthResetFields(flow: flow)
        case .emailPending:
            Image(systemName: "envelope.badge").font(.largeTitle).accessibilityHidden(true)
            Text("注册申请已提交").font(.headline)
            Text("请查看邮箱，按邮件中的链接完成验证后再登录。").font(.callout)
            Button("返回登录") { flow.changePage(.username) }.buttonStyle(PUBOButtonStyle(kind: .primary))
        }
    }
}

struct AuthUsernameField: View {
    @Bindable var flow: AuthFlow
    var showsTitle = true
    var body: some View {
        PUBOAccountField(title: showsTitle ? "用户名" : "", suffix: "@bolubo.com", prefix: "@", compact: true) {
            TextField("用户名", text: $flow.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                .textContentType(.username).accessibilityIdentifier("auth.username")
                .disabled(flow.busy)
                .submitLabel(.continue).onSubmit { if !flow.busy { flow.login() } }
        }
    }
}

struct AuthLoginFields: View {
    @Bindable var flow: AuthFlow
    @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 14
    var body: some View {
        VStack(spacing: 20) {
            avatar
            if flow.page == .username {
                VStack(spacing: 8) { AuthUsernameField(flow: flow, showsTitle: false); continueButton }
            }
            else if flow.page == .password {
                Text("欢迎回来，\(flow.user?.displayName ?? flow.username)").font(.system(size: textSize * 1.1)).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 6) {
                    PUBOPasswordField(title: "密码", value: $flow.password, identifier: "auth.password", compact: true, showsTitle: false)
                        .submitLabel(.continue).onSubmit { flow.login() }.disabled(flow.busy)
                    Button("忘记密码？") { flow.changePage(.forgot) }.font(.footnote).accessibilityIdentifier("auth.forgot")
                }
            } else {
                Text(flow.backup ? "使用备用码登录" : "两步验证").font(.system(size: textSize))
                PUBOAccountField(title: flow.backup ? "备用码" : "动态验证码", compact: true) {
                    TextField(flow.backup ? "32 位备用码" : "6 位动态验证码", text: $flow.otp)
                        .keyboardType(flow.backup ? .asciiCapable : .numberPad)
                        .textInputAutocapitalization(flow.backup ? .characters : .never).autocorrectionDisabled()
                        .textContentType(.oneTimeCode).privacySensitive().accessibilityIdentifier("auth.otp")
                }
                Button(flow.backup ? "使用动态验证码" : "使用备用码") { flow.toggleBackup() }
                    .font(.footnote).accessibilityIdentifier("auth.backup")
            }
            if flow.page != .username { continueButton }
            if flow.page != .username {
                Button("更换账号") { flow.changePage(.username) }.font(.footnote).accessibilityIdentifier("auth.changeAccount")
            }
            if flow.page == .username {
                HStack { Rectangle().frame(height: 1); Text("或者").font(.caption).fixedSize(); Rectangle().frame(height: 1) }.frame(height: 12).foregroundStyle(PUBOTheme.divider)
                VStack(spacing: 6) {
                    Button(action: flow.authorize) { Label("通过本站网页安全登录", systemImage: "key") }.buttonStyle(PUBOButtonStyle(kind: .primary)).disabled(flow.busy).accessibilityIdentifier("auth.web")
                    Text("通行密钥／安全验证使用本站授权窗口").font(.caption2).foregroundStyle(PUBOTheme.secondary).multilineTextAlignment(.center)
                }
            }
        }.frame(minHeight: 336).font(.system(size: textSize))
    }
    private var continueButton: some View {
        Button(action: flow.login) {
            HStack { if flow.busy { ProgressView() }; Label("继续", systemImage: "arrow.right") }
        }.buttonStyle(PUBOButtonStyle(kind: .primary)).disabled(flow.busy || !flow.canLogin)
            .accessibilityIdentifier(flow.page == .username ? "auth.loginContinue" : "auth.submit")
    }
    private var avatar: some View {
        Group {
            if flow.page == .totp { Image(systemName: "key").font(.system(size: 26)).frame(width: 64, height: 64).foregroundStyle(PUBOTheme.accent).background(PUBOTheme.ownBubble, in: Circle()) }
            else if flow.page != .username, let url = safeMediaURL(flow.user?["avatarUrl"].string) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.fill") }
                    .frame(width: 64, height: 64).clipShape(Circle())
            } else { Image(systemName: "person").font(.system(size: 30)).frame(width: 64, height: 64).background(PUBOTheme.button, in: Circle()) }
        }.foregroundStyle(PUBOTheme.secondary).accessibilityHidden(true)
    }
}
