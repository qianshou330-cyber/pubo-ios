import SwiftUI
import UniformTypeIdentifiers
import PUBOCore

struct VerificationApplicationView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var application: JSONValue = .null
    @State private var category = "actor"
    @State private var explanation = ""
    @State private var contact = ""
    @State private var documents: [String: String] = [:]
    @State private var consent = false
    @State private var side = "front"
    @State private var importer = false
    @State private var busy = false
    @State private var loaded = false
    @State private var confirming = false
    @State private var withdrawing = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var revision = UUID()
    private var locked: Bool { ["pending", "approved"].contains(application["status"].string ?? "") }
    private var valid: Bool { loaded && !locked && consent && documents.count == 2 && (1...2000).contains(explanation.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count) && (1...512).contains(contact.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count) }
    var body: some View {
        Form {
            Section("申请状态") {
                Text(["pending": "待审核", "approved": "已认证", "rejected": "未通过", "revoked": "已撤销"][application["status"].string ?? ""] ?? "尚未申请")
                if let reason = application["reviewReason"].string { Text(reason) }
                Button("刷新状态") { Task { await load() } }.disabled(busy)
            }
            Section("申请资料") {
                Picker("认证类别", selection: $category) { Text("演员").tag("actor"); Text("歌手").tag("singer"); Text("模特").tag("model"); Text("内容创作者").tag("contentCreator"); Text("小说作者").tag("novelist"); Text("其他").tag("other") }
                TextField("身份与申请说明（最多 2000 字）", text: $explanation, axis: .vertical).accessibilityIdentifier("verification.description")
                TextField("联系方式", text: $contact).accessibilityIdentifier("verification.contact")
                ForEach([("front", "证件正面"), ("back", "证件背面")], id: \.0) { key, title in
                    Button(documents[key] != nil ? title + " · 已上传" : "上传" + title) { side = key; importer = true }
                }
                Text("仅支持 JPEG、PNG、WebP，每张不超过 10 MiB。材料通过本站认证专用接口上传，不进入公开网盘。本机不保存材料副本；离页后需重新选择尚未提交的材料。").font(.footnote)
                Toggle("同意材料用于认证审核，由本站管理员查看，材料访问会留有记录", isOn: $consent)
                Link("隐私政策", destination: Endpoint.origin.appendingPathComponent("privacy.html"))
                Button("提交认证申请") { confirming = true }.disabled(!valid)
            }.disabled(busy || locked || !loaded)
            if locked { Button("撤回申请／认证", role: .destructive) { withdrawing = true }.disabled(busy) }
            if let error { ErrorBanner(message: error) }
        }.puboForm().navigationTitle("认证申请").privacySensitive().task { await load() }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.jpeg, .png, UTType("org.webmproject.webp") ?? .image]) { result in
                let selectedSide = side; task?.cancel(); task = Task { await upload(result, side: selectedSide) }
            }
            .confirmationDialog("确认提交以上身份资料供人工审核？", isPresented: $confirming) { Button("确认提交") { task = Task { await submit() } } }
            .confirmationDialog("撤回会移除认证状态，并由服务器清理材料。", isPresented: $withdrawing) { Button("确认撤回", role: .destructive) { task = Task { await withdraw() } } }
            .onDisappear { clearSensitive() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { clearSensitive() } else { task = Task { await load() } } }
    }
    private func clearSensitive() { revision = UUID(); task?.cancel(); task = nil; documents = [:]; explanation = ""; contact = ""; consent = false; application = .null; loaded = false }
    private func load() async {
        let request = revision
        do { let result = try await session.call("verification/show"); try Task.checkCancellation(); guard revision == request, scenePhase == .active else { return }; application = result; loaded = true; error = nil; if !result.isNull { category = result["requestedType"].string ?? "actor"; explanation = result["description"].string ?? ""; contact = result["contact"].string ?? "" } }
        catch { self.error = error.localizedDescription }
    }
    private func upload(_ result: Result<URL, Error>, side: String) async {
        busy = true; defer { busy = false }
        let generation = session.generation
        do {
            let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]); guard let size = attributes.fileSize, size > 0, size <= 10 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "每张材料必须小于或等于 10 MiB。") }
            let mime = attributes.contentType?.preferredMIMEType ?? ""; guard ["image/jpeg", "image/png", "image/webp"].contains(mime), let token = session.token else { throw APIError.invalidResponse }
            let data = try Data(contentsOf: url); try Task.checkCancellation()
            let response = try await session.api.upload(path: "verification/upload", data: data, filename: "document." + (attributes.contentType?.preferredFilenameExtension ?? "bin"), mime: mime, fields: ["side": side], token: token)
            try Task.checkCancellation(); guard generation == session.generation, response["side"].string == side, let id = response["id"].string else { throw APIError.invalidResponse }
            documents[side] = id; error = nil
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func submit() async {
        guard valid, !busy else { return }; busy = true; defer { busy = false }
        do {
            let fresh = try await session.call("verification/show"); guard fresh["status"] == application["status"] else { throw APIError(code: "CONFLICT", message: "申请状态已改变，请刷新核对。") }
            do { _ = try await session.call("verification/create", ["type": .string(category), "description": .string(explanation), "contact": .string(contact), "documentIds": .array(["front", "back"].compactMap { documents[$0].map(JSONValue.string) }), "consentVersion": .string("2026-09-30")], mutation: true) }
            catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            let result = try await session.call("verification/show"); guard result["status"].string == "pending", result["description"].string == explanation, result["requestedType"].string == category else { throw APIError.uncertain }
            application = result; documents = [:]; consent = false; error = "申请已提交"
        } catch { self.error = error.localizedDescription }
    }
    private func withdraw() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            do { _ = try await session.call("verification/withdraw", mutation: true) } catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            let result = try await session.call("verification/show"); guard result.isNull || !["pending", "approved"].contains(result["status"].string ?? "") else { throw APIError.uncertain }
            clearSensitive(); application = result; loaded = true; error = "已撤回"; try await session.refreshUser()
        } catch { self.error = error.localizedDescription }
    }
}

