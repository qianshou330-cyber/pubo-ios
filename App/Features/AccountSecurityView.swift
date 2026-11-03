import SwiftUI
import PUBOCore

struct AccountSecurityView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var account: JSONValue = .null
    @State private var password = ""
    @State private var otp = ""
    @State private var email = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var setup: JSONValue = .null
    @State private var setupCode = ""
    @State private var backupCodes: [String] = []
    @State private var action: String?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("操作验证") {
                SecureField("当前密码", text: $password).textContentType(.password)
                TextField("当前动态验证码（已开启时填写）", text: $otp).keyboardType(.numberPad).textContentType(.oneTimeCode)
                Text("敏感操作仍由服务器单独验证密码和验证码。内容仅驻留此页面，离页或进入后台后清除。").font(.footnote)
            }
            Section("邮箱") {
                TextField("邮箱地址", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                Text(account["emailVerified"].bool ? "邮箱已验证" : "邮箱未验证").font(.caption)
                Button("保存邮箱并发送验证邮件") { action = "email" }.disabled(password.isEmpty)
            }
            Section("修改密码") {
                SecureField("新密码", text: $newPassword).textContentType(.newPassword)
                SecureField("再次输入新密码", text: $repeatPassword).textContentType(.newPassword)
                Button("修改密码") { action = "password" }.disabled(password.isEmpty || newPassword.isEmpty || newPassword != repeatPassword)
            }
            Section("动态验证码") {
                Text(account["twoFactorEnabled"].bool ? "已开启" : "未开启")
                if setup.isNull {
                    Button(account["twoFactorEnabled"].bool ? "重新设置验证器" : "设置验证器") { action = "register" }.disabled(password.isEmpty)
                } else {
                    Text("在验证器中添加下列密钥，输入生成的 6 位验证码完成绑定。密钥离页即清除。").font(.footnote)
                    Text(setup["secret"].string ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Text("账号：\(setup["label"].string ?? "") · 发行者：\(setup["issuer"].string ?? "")").font(.caption)
                    TextField("验证器生成的验证码", text: $setupCode).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button("完成绑定") { action = "done" }.disabled(setupCode.count != 6)
                }
                if account["twoFactorEnabled"].bool { Button("关闭动态验证码", role: .destructive) { action = "unregister" }.disabled(password.isEmpty || otp.isEmpty) }
                if !backupCodes.isEmpty { Text("请立即将恢复码保存到安全位置。每个恢复码只能使用一次，本页关闭后不再保留。").font(.footnote); ForEach(backupCodes, id: \.self) { Text($0).font(.system(.body, design: .monospaced)).textSelection(.enabled) }; Button("我已保存恢复码") { backupCodes = [] } }
                Link("通行密钥与网页安全验证 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/security"))
            }
            Section("登录会话") {
                Button("使旧网页登录会话失效", role: .destructive) { action = "regenerate" }.disabled(password.isEmpty)
                Text("刷新主令牌会使使用旧主令牌的登录失效。已授权应用需在“授权会话”中分别撤销；本机草稿保留。").font(.footnote)
            }
            if let error { ErrorBanner(message: error) }
        }.disabled(busy).puboForm().navigationTitle("邮箱与账号安全").privacySensitive().task { await load() }
            .confirmationDialog(confirmText, isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } })) { Button("确认操作", role: action == "unregister" || action == "regenerate" ? .destructive : nil) { if let selected = action { Task { await perform(selected) } } } }
            .onDisappear { clear() }.onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
    }
    private var confirmText: String { switch action { case "email": return "保存邮箱并向新邮箱发送验证邮件？"; case "password": return "修改此账号的登录密码？"; case "unregister": return "关闭动态验证码会降低账号安全性。"; case "regenerate": return "使旧主令牌会话失效？本机可能需要重新授权。"; default: return "确认更新动态验证码设置？" } }
    private func clear() { password = ""; otp = ""; email = ""; newPassword = ""; repeatPassword = ""; setup = .null; setupCode = ""; backupCodes = []; account = .null }
    private func load() async { do { account = try await session.security.call(session: session, path: "i"); email = account["email"].string ?? "" } catch { self.error = error.localizedDescription } }
    private func perform(_ selected: String) async {
        guard !busy else { return }; busy = true; defer { busy = false; password = ""; otp = ""; newPassword = ""; repeatPassword = ""; action = nil }
        do {
            var fields: [String: JSONValue] = ["password": .string(password)]; if !otp.isEmpty { fields["token"] = .string(otp) }
            let endpoint: String
            switch selected {
            case "email": endpoint = "i/update-email"; fields["email"] = email.isEmpty ? .null : .string(email)
            case "password": endpoint = "i/change-password"; fields["currentPassword"] = fields.removeValue(forKey: "password"); fields["newPassword"] = .string(newPassword)
            case "done": endpoint = "i/2fa/done"; fields = ["token": .string(setupCode)]
            case "regenerate": endpoint = "i/regenerate-token"
            default: endpoint = "i/2fa/" + selected
            }
            let result = try await session.security.call(session: session, path: endpoint, fields: fields, mutation: true)
            if selected == "register" { guard result["secret"].string != nil else { throw APIError.uncertain }; setup = result }
            else if selected == "done" { guard !result["backupCodes"].array.isEmpty else { throw APIError.uncertain }; backupCodes = result["backupCodes"].array.compactMap(\.string); setup = .null; setupCode = "" }
            if selected == "regenerate" { session.authorizationRequired = true; session.admin.clear(); session.security.clear(); error = "旧会话已失效，请重新授权；本机草稿保留。"; return }
            await load(); error = selected == "email" ? "已保存邮箱，请查收验证邮件。" : "操作已完成"
        } catch { self.error = error.localizedDescription; if (error as? APIError)?.code == "OUTCOME_UNKNOWN" { self.error = "结果尚未确认，请刷新状态或重新验证密码后核对，不要直接重复操作。"; await load() } }
    }
}

struct AuthorizedSessionsView: View {
    @Environment(AppSession.self) private var session
    @State private var apps: [Record] = []
    @State private var history: [Record] = []
    @State private var more = true
    @State private var busy = false
    @State private var removing: Record?
    @State private var error: String?
    var body: some View {
        List {
            Section("已授权应用") { ForEach(apps) { app in VStack(alignment: .leading) { Text(app["name"].string ?? "未命名授权").font(.headline); Text(app["permission"].array.compactMap(\.string).joined(separator: "、")).font(.caption); if let date = puboDate(app["lastUsedAt"].string) { Text("最近使用 " + date.formatted()).font(.caption) }; Button("撤销授权", role: .destructive) { removing = app } } } }
            Section("登录记录") { ForEach(history) { row in VStack(alignment: .leading) { Text(row["success"].bool ? "登录成功" : "登录失败"); if let date = puboDate(row["createdAt"].string) { Text(date.formatted()).font(.caption) }; Text(row["ip"].string ?? "").font(.caption) } }; if more { Button("加载更多记录") { Task { await loadHistory() } } } }
            if let error { ErrorBanner(message: error) }
        }.disabled(busy).puboForm().navigationTitle("授权会话与登录记录").privacySensitive().task { await loadApps(); await loadHistory() }.refreshable { history = []; await loadApps(); await loadHistory() }
            .confirmationDialog("撤销后此应用无法继续访问账号；当前 App 也可能受影响。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) { Button("确认撤销", role: .destructive) { if let target = removing { Task { await revoke(target) } } } }
            .onDisappear { apps = []; history = [] }
    }
    private func loadApps() async { do { apps = Record.list(try await session.security.call(session: session, path: "i/apps", fields: ["sort": .string("+lastUsedAt")])) } catch { self.error = error.localizedDescription } }
    private func loadHistory() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { var fields: [String: JSONValue] = ["limit": .number(30)]; if let last = history.last { fields["untilId"] = .string(last.id) }; let page = Record.list(try await session.security.call(session: session, path: "i/signin-history", fields: fields)); history = Records.merge(history, page, limit: 10000); more = page.count == 30 } catch { self.error = error.localizedDescription }
    }
    private func revoke(_ target: Record) async {
        busy = true; defer { busy = false }
        do {
            do { _ = try await session.security.call(session: session, path: "i/revoke-token", fields: ["tokenId": .string(target.id)], mutation: true) } catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            await loadApps(); guard !apps.contains(where: { $0.id == target.id }) else { throw APIError.uncertain }; error = "授权已撤销"
        } catch { self.error = error.localizedDescription }
    }
}
