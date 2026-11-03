import SwiftUI
import PUBOCore

struct AccountManagerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var removing: LoginSecret?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Text("仅连接 PUBO。切换保留每个账号的草稿、偏好和待发记录；推送只绑定当前账号。").font(.footnote)
            ForEach(session.savedAccounts, id: \.userID) { account in
                HStack {
                    Button { Task { await select(account) } } label: {
                        VStack(alignment: .leading) { Text(account.displayName ?? account.username ?? account.userID); Text("@" + (account.username ?? account.userID)).font(.caption) }
                    }.disabled(busy || account.userID == session.user?.id).accessibilityIdentifier("accounts.select." + account.userID)
                    Spacer()
                    if account.userID == session.user?.id { Image(systemName: "checkmark").accessibilityLabel("当前账号") }
                    Button("退出", role: .destructive) { removing = account }.disabled(busy)
                }
            }
            Button("添加 PUBO 账号") { adding = true }.accessibilityIdentifier("accounts.add")
            if let error { ErrorBanner(message: error) }
        }.puboForm().navigationTitle("多账号管理").task { session.reloadAccounts() }
            .sheet(isPresented: $adding) { AuthView(addingAccount: true) }
            .confirmationDialog("清除这个账号的本机凭据、草稿、缓存和待发记录？其他账号保留。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("退出这个账号", role: .destructive) { if let account = removing { Task { do { try await session.removeSavedAccount(account.userID) } catch { self.error = error.localizedDescription } } } }
            }
    }
    private func select(_ account: LoginSecret) async {
        busy = true; defer { busy = false }
        do { try await session.switchAccount(account.userID); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct AccountSettingsView: View {
    var body: some View {
        List {
            NavigationLink("认证申请") { VerificationApplicationView() }
            NavigationLink("隐私与内容偏好") { PrivacySettingsView() }
            NavigationLink("通知偏好") { NotificationPreferencesView() }
            NavigationLink("静音与屏蔽") { RelationshipSettingsView() }
            NavigationLink("邮箱、密码与动态验证码") { AdminGate(management: false) { AccountSecurityView() } }
            NavigationLink("授权会话与登录记录") { AdminGate(management: false) { AuthorizedSessionsView() } }
            NavigationLink("邀请") { InvitationsView() }
            NavigationLink("成就") { AchievementsView() }
            NavigationLink("数据导入导出与迁移") { AdminGate(management: false) { AccountDataView() } }
        }.puboForm().navigationTitle("账号与隐私设置")
    }
}

struct PrivacySettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var original: JSONValue = .null
    @State private var values: [String: JSONValue] = [:]
    @State private var error: String?
    @State private var busy = false
    private let switches: [(String, String)] = [("isLocked", "关注需要审批"), ("autoAcceptFollowed", "自动同意已关注用户的申请"), ("isExplorable", "允许探索页推荐"), ("hideOnlineStatus", "隐藏在线状态"), ("publicReactions", "公开我的反应"), ("noCrawle", "请求搜索引擎不要索引"), ("preventAiLearning", "请求禁止 AI 学习"), ("requireSigninToViewContents", "登录后才能查看内容"), ("alwaysMarkNsfw", "默认标记媒体为敏感"), ("autoSensitive", "自动检测敏感媒体"), ("injectFeaturedNote", "接收推荐帖子"), ("receiveAnnouncementEmail", "接收公告邮件"), ("carefulBot", "Bot 关注需要审批"), ("isBot", "标记为 Bot"), ("isCat", "猫猫模式")]
    var body: some View {
        Form {
            if original.isNull { ProgressView("读取当前设置…") }
            ForEach(switches, id: \.0) { key, title in Toggle(title, isOn: Binding(get: { values[key]?.bool ?? false }, set: { values[key] = .bool($0) })).disabled(busy || original.isNull).accessibilityIdentifier("privacy." + key) }
            ForEach([("followingVisibility", "关注列表可见性"), ("followersVisibility", "关注者可见性")], id: \.0) { key, title in
                Picker(title, selection: Binding(get: { values[key]?.string ?? "public" }, set: { values[key] = .string($0) })) { Text("公开").tag("public"); Text("仅关注者").tag("followers"); Text("仅自己").tag("private") }.disabled(busy || original.isNull)
            }
            NavigationLink("静音关键词与服务器") { ContentMuteSettingsView() }
            NavigationLink("旧帖可见性") { OlderNotesPrivacyView() }
            Button("保存修改") { Task { await save() } }.disabled(busy || original.isNull)
            if let error { ErrorBanner(message: error) }
        }.puboForm().navigationTitle("隐私与内容偏好").task { if original.isNull { await load() } }
    }
    private func load() async {
        do { original = try await session.call("i"); for key in switches.map(\.0) + ["followingVisibility", "followersVisibility"] { values[key] = original[key] }; error = nil } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            let changed = values.filter { original[$0.key] != $0.value }; guard !changed.isEmpty else { error = "没有需要保存的修改"; return }
            let fresh = try await session.call("i")
            guard changed.allSatisfy({ fresh[$0.key] == original[$0.key] }) else { throw APIError(code: "CONFLICT", message: "设置已在其他设备改变，请重新进入核对。") }
            do { _ = try await session.call("i/update", changed, mutation: true) } catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            let confirmed = try await session.call("i"); guard changed.allSatisfy({ confirmed[$0.key] == $0.value }) else { throw APIError.uncertain }
            original = confirmed; try await session.refreshUser(); error = "已保存"
        } catch { self.error = error.localizedDescription }
    }
}

struct ContentMuteSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var original: JSONValue = .null
    @State private var soft = ""
    @State private var hard = ""
    @State private var hosts = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Form {
            Text("每行一组；同一行的词以空格分隔并同时匹配。/正则表达式/ 可单独占一行。硬静音会阻止相应帖子进入时间线，已有内容不保证立即移除。").font(.footnote)
            TextField("静音关键词", text: $soft, axis: .vertical); TextField("硬静音关键词", text: $hard, axis: .vertical)
            TextField("静音服务器域名（每行一个）", text: $hosts, axis: .vertical).textInputAutocapitalization(.never)
            Button("保存修改") { Task { await save() } }.disabled(busy || original.isNull)
            if let error { ErrorBanner(message: error) }
        }.puboForm().navigationTitle("关键词与服务器").task {
            do { original = try await session.call("i"); soft = encode(original["mutedWords"]); hard = encode(original["hardMutedWords"]); hosts = original["mutedInstances"].array.compactMap(\.string).joined(separator: "\n") } catch { self.error = error.localizedDescription }
        }
    }
    private func encode(_ value: JSONValue) -> String { value.array.map { $0.string ?? $0.array.compactMap(\.string).joined(separator: " ") }.joined(separator: "\n") }
    private func decode(_ text: String) -> JSONValue { .array(text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { $0.hasPrefix("/") ? .string($0) : .array($0.split(whereSeparator: \.isWhitespace).map { .string(String($0)) }) }) }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            let all: [String: JSONValue] = ["mutedWords": decode(soft), "hardMutedWords": decode(hard), "mutedInstances": .array(hosts.split(whereSeparator: \.isNewline).map { .string(String($0).trimmingCharacters(in: .whitespaces)) })]
            let changed = all.filter { original[$0.key] != $0.value }; guard !changed.isEmpty else { return }
            let fresh = try await session.call("i"); guard changed.allSatisfy({ fresh[$0.key] == original[$0.key] }) else { throw APIError(code: "CONFLICT", message: "设置已改变，请重新进入。") }
            do { _ = try await session.call("i/update", changed, mutation: true) } catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            let result = try await session.call("i"); guard changed.allSatisfy({ result[$0.key] == $0.value }) else { throw APIError.uncertain }; original = result; error = "已保存"
        } catch { self.error = error.localizedDescription }
    }
}

