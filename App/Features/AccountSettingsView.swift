import SwiftUI
import PUBOCore
#if DEBUG
import os
import UIKit
#endif

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
                    }.buttonStyle(.borderless).frame(minHeight: 44).disabled(busy || account.userID == session.user?.id).accessibilityIdentifier("accounts.select." + account.userID)
                    Spacer()
                    if account.userID == session.user?.id { Image(systemName: "checkmark").accessibilityLabel("当前账号") }
                    Button("退出", role: .destructive) { removing = account }.buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44).disabled(busy).accessibilityIdentifier("accounts.remove." + account.userID)
                }
            }
            Button("添加 PUBO 账号") { adding = true }.accessibilityIdentifier("accounts.add")
            if let error { ErrorBanner(message: error) }
        }.puboForm().navigationTitle("多账号管理").task { session.reloadAccounts() }
            .sheet(isPresented: $adding) { AuthView(addingAccount: true) }
            .alert("清除这个账号的本机凭据、草稿、缓存和待发记录？其他账号保留。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { account in
                Button("退出这个账号", role: .destructive) { Task { do { try await session.removeSavedAccount(account.userID) } catch { self.error = error.localizedDescription } } }
                Button("取消", role: .cancel) { removing = nil }
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
            NavigationLink("服务连接") { ServiceConnectionsView() }
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
            ForEach(switches, id: \.0) { key, title in
                let editable = AccountSettingsPolicy.canEditPrivacyOption(key, values: values, loaded: !original.isNull, busy: busy)
                Toggle(title, isOn: Binding(get: { values[key]?.bool ?? false }, set: { updateDraft(key, to: $0) }))
                    .tint(editable ? PUBOTheme.accent : .gray)
                    .foregroundStyle(editable ? PUBOTheme.text : PUBOTheme.secondary)
                    .disabled(!editable)
                    .accessibilityIdentifier("privacy." + key)
                    #if DEBUG
                    .background(PrivacySwitchEventProbe(key: key))
                    #endif
                if key == "requireSigninToViewContents" {
                    Text("启用后，未登录的访客无法查看你发布的内容。链接预览、网页嵌入，以及不支持帖子引用的服务器，都不会显示这些内容。已分发到其他服务器的内容，可能不受此限制。")
                        .font(.footnote)
                        .foregroundStyle(PUBOTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("privacy.requireSigninToViewContents.notice")
                }
            }
            ForEach([("followingVisibility", "关注列表可见性"), ("followersVisibility", "关注者可见性")], id: \.0) { key, title in
                Picker(title, selection: Binding(get: { values[key]?.string ?? "public" }, set: { values[key] = .string($0) })) { Text("公开").tag("public"); Text("仅关注者").tag("followers"); Text("仅自己").tag("private") }.disabled(busy || original.isNull)
            }
            NavigationLink("静音关键词与服务器") { ContentMuteSettingsView() }
            NavigationLink("旧帖可见性") { OlderNotesPrivacyView() }
            Button("保存修改") { Task { await save() } }.disabled(busy || original.isNull)
        }.puboForm().navigationTitle("隐私与内容偏好").task { if original.isNull { await load() } }
            .safeAreaInset(edge: .top) { if let error { Text(error).font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding().background(PUBOTheme.panel).accessibilityIdentifier("privacy.status") } }
    }
    private func updateDraft(_ key: String, to value: Bool) {
        #if DEBUG
        // Synthetic UI runs only: log fixed setting keys/booleans, never user
        // identity, credentials, content, or production account preferences.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let message = "PUBO_PRIVACY_TEST setter key=\(key) value=\(value)"
            Logger(subsystem: "com.pubo.privacy.diagnostics", category: "fixture-draft").notice("\(message, privacy: .public)")
        }
        #endif
        values[key] = .bool(value)
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
            // The baseline and draft must advance together. Otherwise an
            // untouched setting changed remotely becomes a false local edit.
            values = AccountSettingsPolicy.confirmedPrivacyDraft(confirmed, editableKeys: Array(values.keys))
            original = confirmed; try await session.refreshUser(); error = "已保存"
        } catch { self.error = error.localizedDescription }
    }
}

#if DEBUG
// Observation only: keep SwiftUI's Toggle, targets, gestures and accessibility
// intact. Never send actions or modify native state to make a test pass.
private struct PrivacySwitchEventProbe: UIViewRepresentable {
    let key: String
    func makeUIView(context: Context) -> ProbeView { ProbeView(key: key) }
    func updateUIView(_ view: ProbeView, context: Context) { view.scheduleObservation() }

    final class ProbeView: UIView {
        private let key: String
        private weak var observed: UISwitch?
        private var scheduled = false
        private var lastState = ""
        private var observationTimer: Timer?
        private var emitted = 0
        private var heartbeatEmitted = 0
        private var lastHeartbeatUptime: TimeInterval?
        init(key: String) {
            self.key = key
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                observationTimer?.invalidate()
                observationTimer = nil
                detach()
            } else {
                startBoundedObservation()
            }
            scheduleObservation()
        }
        // Only the two failing synthetic privacy rows are polled. SwiftUI can
        // replace its native switch without laying out this background view.
        // Weak capture and window removal bound lifetime; scans and output stay capped.
        private func startBoundedObservation() {
            guard (key == "isLocked" || key == "hideOnlineStatus"),
                  ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                  observationTimer == nil else { return }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
                guard let self, self.window != nil else {
                    timer.invalidate()
                    return
                }
                self.observeNativeControl()
                self.recordHeartbeat()
            }
            observationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        // Separate quota: heartbeat cannot consume native event evidence.
        // A missing heartbeat is a coverage gap, never proof that no touch arrived.
        private func recordHeartbeat() {
            let now = ProcessInfo.processInfo.systemUptime
            guard heartbeatEmitted < 128,
                  lastHeartbeatUptime.map({ now - $0 >= 10 }) ?? true else { return }
            lastHeartbeatUptime = now
            heartbeatEmitted += 1
            let message = "PUBO_PRIVACY_TEST heartbeat key=\(key) pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(now) probe=\(ObjectIdentifier(self)) sequence=\(heartbeatEmitted) window=\(window != nil) timerValid=\(observationTimer?.isValid ?? false) attached=\(observed != nil) lastObservedState=\(lastState) quotaExhausted=\(heartbeatEmitted == 128)"
            Logger(subsystem: "com.pubo.privacy.diagnostics", category: "fixture-draft").notice("\(message, privacy: .public)")
        }
        deinit { observationTimer?.invalidate() }
        override func layoutSubviews() { super.layoutSubviews(); scheduleObservation() }
        func scheduleObservation() {
            guard ProcessInfo.processInfo.arguments.contains("--ui-testing"), !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                self.observeNativeControl()
            }
        }
        private func observeNativeControl() {
            guard let window else { detach(); return }
            let probeBounds = convert(bounds, to: window)
            guard !probeBounds.isEmpty, !probeBounds.isInfinite else { detach(); return }
            var scanned = 0
            var exceededBudget = false
            func switches(in view: UIView) -> [UISwitch] {
                scanned += 1
                guard scanned <= 100 else { exceededBudget = true; return [] }
                guard !(view is UITableView), !(view is UICollectionView) else { return [] }
                if let control = view as? UISwitch { return [control] }
                return view.subviews.flatMap { switches(in: $0) }
            }
            var parent = superview
            // Stop at the first ancestor containing any switches; ambiguity
            // is logged instead of attaching to a different settings row.
            for _ in 0..<8 {
                guard let ancestor = parent else { break }
                let controls = switches(in: ancestor)
                if exceededBudget { detach(); logState("scan-budget-exceeded"); return }
                if !controls.isEmpty {
                    guard controls.count == 1, let control = controls.first,
                          probeBounds.contains(control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: window)) else {
                        detach()
                        logState("ambiguous count=\(controls.count)"); return
                    }
                    if observed !== control {
                        observed?.removeTarget(self, action: nil, for: .allEvents)
                        observed = control
                        control.addTarget(self, action: #selector(touchDown(_:)), for: .touchDown)
                        control.addTarget(self, action: #selector(touchUp(_:)), for: [.touchUpInside, .touchUpOutside])
                        control.addTarget(self, action: #selector(touchCancel(_:)), for: .touchCancel)
                        control.addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
                        log("attached instance=\(ObjectIdentifier(control))")
                    }
                    let bounds = control.convert(control.bounds, to: window)
                    let hit = window.hitTest(CGPoint(x: bounds.midX, y: bounds.midY), with: nil)
                    let belongs = hit.map { $0 === control || $0.isDescendant(of: control) } ?? false
                    logState("layout instance=\(ObjectIdentifier(control)) on=\(control.isOn) enabled=\(control.isEnabled) frame=\(bounds) centerHitsControl=\(belongs)")
                    return
                }
                if ancestor is UITableViewCell || ancestor is UICollectionViewCell { break }
                parent = ancestor.superview
            }
            detach()
            logState("native-not-found")
        }
        private func detach() {
            if let observed { log("detached instance=\(ObjectIdentifier(observed))") }
            observed?.removeTarget(self, action: nil, for: .allEvents)
            observed = nil
        }
        @objc private func touchDown(_ control: UISwitch) { log("touchDown on=\(control.isOn)") }
        @objc private func touchUp(_ control: UISwitch) { log("touchUp on=\(control.isOn)") }
        @objc private func touchCancel(_ control: UISwitch) { log("touchCancel on=\(control.isOn)") }
        @objc private func valueChanged(_ control: UISwitch) { log("valueChanged on=\(control.isOn)") }
        private func logState(_ state: String) {
            guard lastState != state else { return }; lastState = state; log(state)
        }
        private func log(_ stage: String) {
            guard emitted < 128 else { return }
            emitted += 1
            let message = "PUBO_PRIVACY_TEST native key=\(key) \(stage)"
            Logger(subsystem: "com.pubo.privacy.diagnostics", category: "fixture-draft").notice("\(message, privacy: .public)")
        }
    }
}
#endif

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


