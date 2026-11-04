import SwiftUI
import PUBOCore

struct AuthResetFields: View {
    @Bindable var flow: AuthFlow
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if flow.session.meta["enableEmail"].bool {
                Text("通过邮箱重置").font(.headline)
                AuthUsernameField(flow: flow)
                AuthEmailField(flow: flow)
                Button("发送重置邮件", action: flow.emailReset).buttonStyle(PUBOButtonStyle())
                    .disabled(flow.busy || flow.username.isEmpty || flow.email.isEmpty).accessibilityIdentifier("auth.emailReset")
                Text("邮件中的重置链接由本站网页处理。").font(.footnote).foregroundStyle(PUBOTheme.secondary)
                Divider()
            } else { Text("本站暂未启用邮件找回。可使用已绑定的手机号码，或联系管理员。").font(.footnote) }
            Text("通过手机重置").font(.headline)
            AuthPhoneFields(flow: flow, reset: true)
            PUBOPasswordField(title: "新密码", value: $flow.password, identifier: "auth.password", newPassword: true, compact: true)
            Text("至少 8 个字符").font(.footnote).foregroundStyle(PUBOTheme.secondary)
            PUBOPasswordField(title: "再次输入密码", value: $flow.confirmation, identifier: "auth.confirmation", newPassword: true, compact: true)
            AuthPasswordMatch(flow: flow)
            Button(action: flow.phoneReset) { HStack { if flow.busy { ProgressView() }; Text("重置密码") } }
                .buttonStyle(PUBOButtonStyle(kind: .primary, fullWidth: true))
                .disabled(flow.busy || !AuthenticationInput.validPhone(flow.phone) || !AuthenticationInput.validCode(flow.code) || flow.password.count < 8 || flow.password != flow.confirmation)
                .accessibilityIdentifier("auth.phoneReset")
            Button("返回登录") { flow.changePage(.username) }.font(.footnote).accessibilityIdentifier("auth.backToLogin")
        }
    }
}
