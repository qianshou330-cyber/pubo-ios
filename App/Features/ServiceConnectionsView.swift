import SwiftUI
import PUBOCore

struct ServiceConnectionsView: View {
    @Environment(AppSession.self) private var session
    @State private var hooks: [Record] = []
    @State private var error: String?
    var body: some View {
        AdminGate(management: false) {
            List {
                NavigationLink("生成访问令牌") { PersonalTokenView() }
                NavigationLink("管理已授权应用") { AdminGate(management: false) { AuthorizedSessionsView() } }
                Section("Webhook") {
                    NavigationLink("创建 Webhook") { PersonalWebhookEditor() }
                    ForEach(hooks) { hook in NavigationLink { PersonalWebhookEditor(webhookID: hook.id) } label: { VStack(alignment: .leading) { Text(hook["name"].string ?? "Webhook"); Text(hook["active"].bool ? "已启用" : "已暂停").font(.caption) } } }
                }
                Link("API 控制台 · 网页版", destination: Endpoint.origin.appendingPathComponent("api-console"))
                if let error { ErrorBanner(message: error) }
            }.puboForm().navigationTitle("服务连接").task { await load() }.refreshable { await load() }.onDisappear { hooks = [] }
        }
    }
    private func load() async {
        do {
            let response = try await session.security.call(session: session, path: "i/webhooks/list")
            // The list API includes secrets; retain only non-secret summary fields.
            hooks = response.array.map { Record(.object($0.object.filter { ["id", "name", "active"].contains($0.key) })) }; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct PersonalTokenView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var selected = Set<String>()
    @State private var token = ""
    @State private var showing = false
    @State private var confirm = false
    @State private var busy = false
    @State private var locked = false
    @State private var error: String?
    private let key = "personal-token-create"
    private var permissions: [String] {
        guard let url = Bundle.main.url(forResource: "TokenPermissions", withExtension: "json"), let data = try? Data(contentsOf: url), let all = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return all.filter { !$0.contains(":admin:") || session.user?["isAdmin"].bool == true || session.user?["isModerator"].bool == true }
    }
    var body: some View {
        AdminGate(management: false) {
            Form {
                Text("只选择应用实际需要的权限。令牌可代表你访问账号，生成后仅在本页显示一次。").font(.footnote)
                TextField("令牌名称", text: $name)
                ForEach(permissions, id: \.self) { permission in Toggle(permission, isOn: Binding(get: { selected.contains(permission) }, set: { if $0 { selected.insert(permission) } else { selected.remove(permission) } })) }
                Button("生成令牌") { confirm = true }.disabled(busy || locked || name.isEmpty || selected.isEmpty)
                if !token.isEmpty { Section("新令牌") { Toggle("显示令牌", isOn: $showing); if showing { Text(token).font(.system(.body, design: .monospaced)).textSelection(.enabled).privacySensitive() }; Text("离页后清除。如果未保存，可在授权应用中撤销后重新生成。").font(.caption) } }
                if locked && token.isEmpty { Text("上次生成结果尚未确认。请先到已授权应用核对并撤销不再需要的令牌。"); NavigationLink("检查已授权应用") { AdminGate(management: false) { AuthorizedSessionsView() } }; Button("已核对，允许重新生成") { do { try session.markPendingAction(key, pending: false); locked = false } catch { self.error = error.localizedDescription } } }
                if let error { ErrorBanner(message: error) }
            }.puboForm().navigationTitle("访问令牌").privacySensitive().task { locked = session.hasPendingAction(key) }
                .alert("为所选权限创建访问令牌？", isPresented: $confirm) { Button("创建") { Task { await create() } }; Button("取消", role: .cancel) {} }
                .onDisappear { token = ""; showing = false }.onChange(of: scenePhase) { _, phase in if phase != .active { token = ""; showing = false } }
        }
    }
    private func create() async {
        guard !busy && !locked else { return }; busy = true; defer { busy = false }
        do {
            try session.markPendingAction(key, pending: true); locked = true
            let response = try await session.security.call(session: session, path: "miauth/gen-token", fields: ["session": .null, "name": .string(name), "permission": .strings(selected.sorted())], mutation: true)
            guard let created = response["token"].string, !created.isEmpty else { throw APIError.uncertain }
            token = created; try session.markPendingAction(key, pending: false); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct PersonalWebhookEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    var webhookID: String?
    @State private var baseline: JSONValue = .null
    @State private var name = ""
    @State private var url = ""
    @State private var secret = ""
    @State private var changeSecret = false
    @State private var events = Set<String>()
    @State private var active = true
    @State private var loaded = false
    @State private var busy = false
    @State private var locked = false
    @State private var action: String?
    @State private var error: String?
    private var key: String { "personal-webhook-" + (webhookID ?? "create") }
    private let eventNames = [("mention", "提及我"), ("unfollow", "取消关注"), ("follow", "我关注了用户"), ("followed", "被关注"), ("note", "发布帖子"), ("reply", "回复"), ("renote", "转发"), ("reaction", "反应")]
    var body: some View {
        AdminGate(management: false) {
            Form {
                TextField("名称", text: $name); TextField("接收地址", text: $url).textInputAutocapitalization(.never).keyboardType(.URL)
                Text("所选事件会把账号事件数据发送到这个地址，请确认接收方。").font(.footnote)
                if webhookID != nil { Toggle("启用", isOn: $active); Toggle("修改密钥", isOn: $changeSecret) }
                if changeSecret || webhookID == nil { SecureField("密钥（留空表示不设置）", text: $secret) }
                ForEach(eventNames, id: \.0) { event, title in Toggle(title, isOn: Binding(get: { events.contains(event) }, set: { if $0 { events.insert(event) } else { events.remove(event) } })) }
                Button("保存") { action = "save" }.disabled(!loaded || locked || busy)
                if webhookID != nil { Button("删除 Webhook", role: .destructive) { action = "delete" }.disabled(busy || locked) }
                if locked { Text("操作结果待核对，请返回服务连接检查当前记录。"); Button("已核对，重新读取") { Task { do { try session.markPendingAction(key, pending: false); locked = false; await load() } catch { self.error = error.localizedDescription } } } }
                if let error { ErrorBanner(message: error) }
            }.disabled(busy).puboForm().navigationTitle(webhookID == nil ? "创建 Webhook" : "修改 Webhook").task { await load() }
                .alert("确认修改账号事件发送设置？", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), presenting: action) { operation in Button(operation == "delete" ? "确认删除" : "确认保存", role: operation == "delete" ? .destructive : nil) { Task { await save(operation) } }; Button("取消", role: .cancel) { action = nil } }
                .onDisappear { secret = ""; baseline = .null; loaded = false }
        }
    }
    private func call(_ operation: String, _ fields: [String: JSONValue] = [:], mutation: Bool = false) async throws -> JSONValue { try await session.security.call(session: session, path: "i/webhooks/" + operation, fields: fields, mutation: mutation) }
    private func load() async {
        do {
            locked = session.hasPendingAction(key)
            if let webhookID { let value = try await call("show", ["webhookId": .string(webhookID)]); baseline = .object(value.object.filter { $0.key != "secret" }); name = value["name"].string ?? ""; url = value["url"].string ?? ""; active = value["active"].bool; events = Set(value["on"].array.compactMap(\.string)) }
            loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ operation: String) async {
        guard !busy && !locked else { return }; busy = true; defer { busy = false; secret = "" }
        do {
            var fields: [String: JSONValue] = [:]
            if let webhookID { fields["webhookId"] = .string(webhookID) }
            if operation != "delete" {
                guard (1...100).contains(name.count), url.count <= 1024, let target = URL(string: url), ["https", "http"].contains(target.scheme ?? ""), target.host != nil, secret.count <= 1024 else { throw APIError(code: "INVALID_INPUT", message: "请填写有效名称、接收地址和密钥。") }
                fields.merge(["name": .string(name), "url": .string(url), "on": .strings(events.sorted())], uniquingKeysWith: { _, new in new })
                if webhookID != nil { fields["active"] = .bool(active) }
                if changeSecret || webhookID == nil { fields["secret"] = .string(secret) }
            }
            if let webhookID {
                let fresh = try await call("show", ["webhookId": .string(webhookID)])
                guard ["name", "url", "active", "on"].allSatisfy({ fresh[$0] == baseline[$0] }) else { throw APIError(code: "CONFLICT", message: "Webhook 已在其他设备修改，请重新进入核对。") }
                if operation != "delete" { fields = fields.filter { $0.key == "webhookId" || $0.key == "secret" || fresh[$0.key] != $0.value } }
            }
            try session.markPendingAction(key, pending: true); locked = true
            let endpoint = operation == "delete" ? "delete" : webhookID == nil ? "create" : "update"
            do { _ = try await call(endpoint, fields, mutation: true) }
            catch { if endpoint == "create" || (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            if let webhookID {
                if operation == "delete" { let remaining = try await call("list"); guard !remaining.array.contains(where: { $0["id"].string == webhookID }) else { throw APIError.uncertain } }
                else { let actual = try await call("show", ["webhookId": .string(webhookID)]); guard fields.allSatisfy({ $0.key == "webhookId" || actual[$0.key] == $0.value }) else { throw APIError.uncertain } }
            }
            try session.markPendingAction(key, pending: false); locked = false; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
