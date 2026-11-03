import SwiftUI
import PUBOCore

struct NativeAdminView: View {
    @Environment(AppSession.self) private var session
    @State private var query = ""
    private var available: [AdminEndpoint] { (AdminCatalog.shared?.endpoints ?? []).filter { $0.available(to: session.user?.raw ?? .null) && $0.id != "admin/verification/document" } }
    private var groups: [String] { Array(Set(available.map { AdminCatalog.group($0.id) })).sorted() }
    var body: some View {
        AdminGate {
            List {
                Section { Text("操作权限由服务器实时检查。离开前台或闲置 15 分钟后，需要重新验证。").font(.footnote) }
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(available.filter { AdminCatalog.group($0.id) == group && (query.isEmpty || AdminCatalog.title($0.id).localizedCaseInsensitiveContains(query) || group.contains(query)) }) { endpoint in
                            NavigationLink { AdminOperationView(endpoint: endpoint) } label: { Label(AdminCatalog.title(endpoint.id), systemImage: endpoint.mutation ? "square.and.pencil" : "list.bullet.rectangle") }.accessibilityIdentifier("admin.operation." + endpoint.id)
                        }
                    }
                }
                if available.isEmpty { Text("当前账号没有可用的后台功能，或权限已撤销。") }
            }.puboForm().searchable(text: $query, prompt: "搜索管理功能").navigationTitle("管理后台")
                .task { try? await session.refreshUser() }
        }
    }
}

struct AdminOperationView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let endpoint: AdminEndpoint
    var seed: JSONValue = .null
    var source: String = ""
    var context: [String: JSONValue] = [:]
    @State private var values: [String: JSONValue] = [:]
    @State private var baseline: JSONValue = .null
    @State private var result: JSONValue = .null
    @State private var busy = false
    @State private var initialized = false
    @State private var confirmation = false
    @State private var locked = false
    @State private var inspected = false
    @State private var error: String?
    @State private var status: String?
    @State private var fieldSearch = ""
    @State private var revealPassword = false
    @State private var requestGeneration = UUID()
    private var schema: JSONValue { AdminSchema.form(endpoint.schema) }
    private var keys: [String] { schema["properties"].object.keys.sorted().filter { $0 != "captchaResult" && (fieldSearch.isEmpty || AdminLabels.title($0).localizedCaseInsensitiveContains(fieldSearch) || $0.localizedCaseInsensitiveContains(fieldSearch)) } }
    private var pendingKey: String { AdminOperations.pendingKey(endpoint.id) }
    private var currentPayload: [String: JSONValue] { AdminOperations.payload(endpoint, values: values, original: baseline) }
    var body: some View {
        AdminGate {
            Form {
                if let error { Section { ErrorBanner(message: error) } }
                if let status { Section { Text(status).accessibilityIdentifier("admin.status") } }
                if locked { uncertainty }
                if endpoint.id == "admin/captcha/save" { Section { Text("验证码服务的连通性挑战须在官方网页完成。请在网页验证并保存；不会要求手工复制挑战令牌。"); Link("完成官方验证 · 网页版", destination: Endpoint.origin.appendingPathComponent("admin/security")) } }
                if endpoint.mutation { Section { Text(AdminOperations.effect(endpoint.id)).font(.footnote); if AdminOperations.snapshot(endpoint.id, fields: values) != nil { Button("读取最新记录后编辑") { Task { await reloadBaseline() } }.disabled(busy || locked) } } }
                if keys.count > 18 { Section { TextField("查找设置项", text: $fieldSearch) } }
                Section(endpoint.mutation ? "编辑内容" : "筛选条件") {
                    ForEach(keys, id: \.self) { key in field(key) }
                }.disabled(busy || locked)
                Section {
                    Button(endpoint.mutation ? "核对并提交" : "读取数据") { if endpoint.mutation { validateAndConfirm() } else { Task { await fetch(more: false) } } }.disabled(busy || locked || endpoint.id == "admin/captcha/save").accessibilityIdentifier("admin.submit")
                    if busy { ProgressView() }
                }
                if !result.isNull { Section("服务器返回") { AdminResultView(value: result, source: endpoint.id, context: values) } }
                if endpoint.id == "admin/reset-password", let password = result["password"].string {
                    Section("新临时密码") { Text("请安全告知账号持有人，并让其及时更换。离开此页后不保留。").font(.footnote); Toggle("显示临时密码", isOn: $revealPassword); if revealPassword { Text(password).font(.system(.body, design: .monospaced)).textSelection(.enabled).privacySensitive() } }
                }
                if canLoadMore { Button("加载下一页") { Task { await fetch(more: true) } }.disabled(busy) }
            }.puboForm().navigationTitle(AdminCatalog.title(endpoint.id))
                .task { await initialize() }
                .alert("确认“\(AdminCatalog.title(endpoint.id))”？", isPresented: $confirmation) {
                    Button("确认提交", role: destructive ? .destructive : nil) { Task { await submit() } }
                    Button("取消", role: .cancel) {}
                } message: { Text(AdminOperations.effect(endpoint.id) + "\n涉及：" + currentPayload.keys.sorted().map(AdminLabels.title).joined(separator: "、")) }
                .onChange(of: scenePhase) { _, phase in if phase != .active { clearSensitive() } }
                .onChange(of: session.admin.unlocked) { _, unlocked in if !unlocked { clearSensitive() } }
                .onDisappear { if endpoint.id == "admin/reset-password" { result = .null; revealPassword = false } }
        }
    }
    @ViewBuilder private func field(_ key: String) -> some View {
        if values[key] != nil {
            AdminValueField(key: key, schema: schema["properties"][key], value: Binding(get: { values[key] ?? .null }, set: { values[key] = $0 })).accessibilityIdentifier("admin.field." + key)
            if !schema["required"].array.contains(.string(key)) { Button("不提交“\(AdminLabels.title(key))”") { values.removeValue(forKey: key) }.font(.caption) }
        } else { Button("设置“\(AdminLabels.title(key))”") { values[key] = AdminSchema.initial(schema["properties"][key]) }.accessibilityIdentifier("admin.enable." + key) }
    }
    private var uncertainty: some View {
        Section("上次操作尚未确认") {
            Text("为避免重复执行，此操作已暂停。先查看对应列表、记录或审核日志，核对服务器实际结果。")
            NavigationLink("查看审核日志") { if let logs = AdminCatalog.shared?.endpoint("admin/show-moderation-logs") { AdminOperationView(endpoint: logs) } }
            Toggle("我已核对服务器结果", isOn: $inspected)
            Button("结束核对，允许再次编辑") { do { try session.markPendingAction(pendingKey, pending: false); locked = false; inspected = false; status = "已结束人工核对；不会自动重发。" } catch { self.error = error.localizedDescription } }.disabled(!inspected)
        }
    }
    private var destructive: Bool { endpoint.id.contains("delete") || endpoint.id.contains("suspend") || endpoint.id.contains("clear") || endpoint.id.contains("cleanup") }
    private var canLoadMore: Bool { !endpoint.mutation && !result.array.isEmpty && (schema["properties"].object["untilId"] != nil || schema["properties"].object["offset"] != nil || schema["properties"].object["page"] != nil) && result.array.count % max(1, values["limit"]?.int ?? 30) == 0 }
    private func initialize() async {
        guard !initialized else { return }; initialized = true
        locked = session.hasPendingAction(pendingKey)
        values = AdminOperations.seed(seed, for: endpoint, source: source, context: context)
        if !endpoint.mutation, (try? AdminSchema.validate(.object(values), schema: endpoint.schema)) != nil { await fetch(more: false) }
        else if endpoint.mutation, AdminOperations.snapshot(endpoint.id, fields: values) != nil, !locked { await reloadBaseline() }
    }
    private func reloadBaseline() async {
        guard !busy, let request = AdminOperations.snapshot(endpoint.id, fields: values) else { return }
        busy = true; defer { busy = false }; let generation = requestGeneration
        do {
            let latest = try await AdminOperations.read(request, session: session)
            guard generation == requestGeneration else { return }
            baseline = latest
            values = AdminOperations.seed(AdminOperations.comparable(latest, endpoint: endpoint.id), for: endpoint, source: endpoint.id, context: values.filter { AdminOperations.identities.contains($0.key) })
            error = nil; status = "已读取最新内容。仅保存实际修改字段。"
        } catch { if generation == requestGeneration { self.error = error.localizedDescription } }
    }
    private func fetch(more: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }; let generation = requestGeneration
        do {
            var query = values
            if more {
                if schema["properties"].object["offset"] != nil { query["offset"] = .number(Double((values["offset"]?.int ?? 0) + (values["limit"]?.int ?? 30))) }
                else if schema["properties"].object["page"] != nil { query["page"] = .number(Double((values["page"]?.int ?? 1) + 1)) }
                else { query["untilId"] = result.array.last?["id"] }
            }
            try AdminSchema.validate(.object(query), schema: endpoint.schema)
            let response = try await session.admin.call(session: session, path: endpoint.id, fields: query)
            guard generation == requestGeneration else { return }
            if more { var seen = Set(result.array.compactMap { $0["id"].string }); result = .array(result.array + response.array.filter { row in guard let id = row["id"].string else { return true }; return seen.insert(id).inserted }); values = query } else { result = response }
            error = nil; status = response.array.isEmpty && response.object.isEmpty ? "读取完成；暂无记录。" : "已读取服务器最新结果。"
        } catch { if generation == requestGeneration { self.error = error.localizedDescription } }
    }
    private func validateAndConfirm() {
        do { try AdminSchema.validate(.object(currentPayload), schema: endpoint.schema); confirmation = true; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func submit() async {
        guard !busy, !locked else { return }; busy = true; defer { busy = false }; let generation = requestGeneration
        var sent = false
        var definitelyRejected = false
        do {
            try await session.refreshUser()
            guard endpoint.available(to: session.user?.raw ?? .null) else { throw APIError(code: "PERMISSION_DENIED", message: "当前账号已无此操作权限。") }
            let body = currentPayload
            if let request = AdminOperations.snapshot(endpoint.id, fields: values) {
                guard !baseline.isNull else { throw APIError(code: "READ_REQUIRED", message: "请先读取最新记录。") }
                let fresh = try await AdminOperations.read(request, session: session)
                let compareKeys = Set(body.keys).union(["status", "updatedAt", "reviewedAt"])
                let old = AdminOperations.comparable(baseline, endpoint: endpoint.id), new = AdminOperations.comparable(fresh, endpoint: endpoint.id)
                guard compareKeys.allSatisfy({ AdminOperations.identities.contains($0) || old[$0] == new[$0] }) else { throw APIError(code: "CONFLICT", message: "记录已被修改，请重新读取后再操作。") }
            }
            try AdminSchema.validate(.object(body), schema: endpoint.schema)
            guard generation == requestGeneration else { throw CancellationError() }
            try session.markPendingAction(pendingKey, pending: true); locked = true; sent = true
            var response: JSONValue = .null
            do { response = try await session.admin.call(session: session, path: endpoint.id, fields: body, mutation: true) }
            catch {
                if let failure = error as? APIError, failure.code != "OUTCOME_UNKNOWN" { definitelyRejected = true; throw error }
                guard (error as? APIError)?.code == "OUTCOME_UNKNOWN", let verified = try? await AdminOperations.verify(endpoint, fields: body, session: session) else { throw error }
                response = verified
            }
            guard generation == requestGeneration else { return }
            if let verified = try await AdminOperations.verify(endpoint, fields: body, session: session) { response = verified }
            result = response; status = "服务器已受理。异步清理、导入或队列任务请在对应列表查看完成结果。"
            try session.markPendingAction(pendingKey, pending: false); locked = false; error = nil
            if AdminOperations.snapshot(endpoint.id, fields: values) != nil && !destructive { baseline = .null; status = "服务器已受理。再次编辑前请读取最新记录。" }
            for key in values.keys where AdminSchema.isSecret(key) { values.removeValue(forKey: key) }
        } catch {
            guard generation == requestGeneration else { return }
            // A definite API rejection did not mutate; transport failures stay durably locked.
            if sent && definitelyRejected { try? session.markPendingAction(pendingKey, pending: false); locked = false }
            self.error = error.localizedDescription
        }
    }
    private func clearSensitive() { requestGeneration = UUID(); baseline = .null; result = .null; values = [:]; initialized = false; status = nil; error = nil }
}

struct AdminResultView: View {
    @Environment(AppSession.self) private var session
    let value: JSONValue
    var source: String = ""
    var context: [String: JSONValue] = [:]
    private var safe: JSONValue { AdminSchema.redacted(value) }
    var body: some View {
        Group {
            if case .array(let items) = safe {
                if items.isEmpty { Text("暂无记录") }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    NavigationLink { AdminRecordView(value: item, source: source, context: context) } label: { VStack(alignment: .leading) { Text(summary(item, index: index)); if let id = item["id"].string { Text(id).font(.caption).foregroundStyle(.secondary) } } }
                }
            } else if case .object(let fields) = safe {
                ForEach(fields.keys.sorted(), id: \.self) { key in
                    if case .object = fields[key]! { NavigationLink(AdminLabels.title(key)) { AdminGate { List { AdminResultView(value: fields[key]!, source: source, context: context) }.puboForm().navigationTitle(AdminLabels.title(key)) } } }
                    else if case .array = fields[key]! { NavigationLink { AdminGate { List { AdminResultView(value: fields[key]!, source: source, context: context) }.puboForm().navigationTitle(AdminLabels.title(key)) } } label: { LabeledContent(AdminLabels.title(key), value: AdminLabels.value(fields[key]!)) } }
                    else { VStack(alignment: .leading, spacing: 4) { Text(AdminLabels.title(key)).font(.caption).foregroundStyle(.secondary); Text(AdminLabels.value(fields[key]!)).textSelection(.enabled) } }
                }
            } else { Text(AdminLabels.value(safe)) }
        }
    }
    private func summary(_ item: JSONValue, index: Int) -> String { for key in ["title", "name", "username", "host", "type", "status", "id"] { if let text = item[key].string, !text.isEmpty { return text } }; return item.object.isEmpty ? AdminLabels.value(item) : "记录 \(index + 1)" }
}

struct AdminRecordView: View {
    @Environment(AppSession.self) private var session
    let value: JSONValue
    let source: String
    var context: [String: JSONValue]
    private var actions: [AdminEndpoint] { (AdminCatalog.shared?.endpoints ?? []).filter { $0.available(to: session.user?.raw ?? .null) && AdminCatalog.group($0.id) == AdminCatalog.group(source) && $0.id != source && $0.id != "admin/verification/document" && !$0.id.hasSuffix("/create") && !$0.id.hasSuffix("/list") } }
    var body: some View {
        AdminGate { List {
            Section { AdminResultView(value: value) }
            if source.contains("verification/"), let id = value["id"].string { NavigationLink("查看申请与受保护材料") { AdminVerificationDetail(applicationID: id) } }
            if !value["id"].isNull || !value["host"].isNull || !value["inbox"].isNull { Section("操作此记录") { ForEach(actions) { endpoint in NavigationLink(AdminCatalog.title(endpoint.id)) { AdminOperationView(endpoint: endpoint, seed: value, source: source, context: context) } } } }
        }.puboForm().navigationTitle("记录详情") }
    }
}
