import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PUBOCore

struct ComposeDraft: Codable {
    var text = ""
    var cw = ""
    var useCW = false
    var visibility = "public"
    var files: [Record] = []
    var outcome = "ready"
    var lastFailure: String?
}

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    var replyTo: Record? = nil
    var renote: Record? = nil
    var onSent: () -> Void
    @State private var draft = ComposeDraft()
    @State private var selected: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var error: String?
    @State private var restored = false
    @State private var ownerID: String?
    @State private var confirmRetry = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var choosingEmoji = false
    private var key: String { "compose-" + (replyTo?.id ?? renote?.id ?? "new") }

    var body: some View {
        NavigationStack {
            Form {
                if let replyTo { Section("回复 \(replyTo.user.displayName)") { Text(replyTo.text).lineLimit(3) } }
                if let renote { Section("引用转发") { Text(renote.text).lineLimit(3) } }
                Section {
                    TextEditor(text: $draft.text).scrollContentBackground(.hidden).frame(minHeight: 160).accessibilityIdentifier("compose.text")
                    Button("插入表情") { choosingEmoji = true }
                    Picker("可见范围", selection: $draft.visibility) { Text("公开").tag("public"); Text("首页").tag("home"); Text("关注者").tag("followers") }
                    Toggle("内容警告", isOn: $draft.useCW)
                    if draft.useCW { TextField("内容提示", text: $draft.cw) }
                    PhotosPicker(selection: $selected, maxSelectionCount: max(0, 16 - draft.files.count), matching: .any(of: [.images, .videos])) { Label("添加图片或视频", systemImage: "photo.on.rectangle") }.disabled(busy || draft.files.count >= 16 || draft.outcome != "ready")
                    ForEach(draft.files) { file in
                        HStack { Text(file["name"].string ?? "已上传附件"); Spacer(); Button("移除") { draft.files.removeAll { $0.id == file.id }; save() }.listRowBackground(PUBOTheme.panel).disabled(busy || draft.outcome != "ready") }
                    }
                }.listRowBackground(PUBOTheme.panel).disabled(busy || draft.outcome != "ready")
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if draft.outcome != "ready" {
                    Section("发送结果待确认") {
                        Text("请先检查自己的帖子。此接口不能保证重复提交只产生一条帖子，客户端不会自动重发。")
                        if let user = session.user { NavigationLink("查看我的帖子") { ProfileView(userID: user.id) } }
                        Button("已核对记录，恢复手动提交") { confirmRetry = true }
                    }
                }
            }.puboForm().navigationTitle(replyTo == nil ? "发布帖子" : "回复帖子")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("保存并关闭") { if save() { dismiss() } }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("发布") { Task { await send() } }.buttonStyle(PUBOButtonStyle(kind: .publish)).disabled(busy || draft.outcome != "ready" || (draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.files.isEmpty && renote == nil)).accessibilityIdentifier("compose.send") }
                }
                .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
                .task {
                    guard !restored else { return }; restored = true; ownerID = session.user?.id
                    if let account = session.user?.id, let saved = try? session.store?.read(ComposeDraft.self, account: account, key: key) { draft = saved; error = saved.lastFailure; if draft.outcome == "sending" { draft.outcome = "uncertain" } }
                }
                .onChange(of: draft.text) { _, _ in save() }
                .onChange(of: draft.cw) { _, _ in save() }
                .onChange(of: draft.visibility) { _, _ in save() }
                .onChange(of: draft.useCW) { _, _ in save() }
                .onChange(of: selected) { _, values in uploadTask = Task { await upload(values) } }
                .onDisappear { uploadTask?.cancel() }
                .sheet(isPresented: $choosingEmoji) { ReactionPicker { draft.text += $0 } }
                .confirmationDialog("只有确认原帖未发布时才重新提交，否则可能产生重复帖子。", isPresented: $confirmRetry) { Button("确认恢复手动提交") { draft.outcome = "ready"; save() } }
        }.interactiveDismissDisabled(busy)
    }
    @discardableResult private func save() -> Bool {
        guard restored, let account = session.user?.id, account == ownerID else { return false }
        if session.testMode { return true }
        guard let store = session.store else { error = "本机存储不可用，暂时不能安全发送。"; return false }
        do { try store.save(draft, account: account, key: key); return true } catch { self.error = "草稿保存失败，请暂时不要关闭页面。"; return false }
    }
    private func upload(_ items: [PhotosPickerItem]) async {
        guard !busy, draft.outcome == "ready" else { return }
        busy = true; defer { busy = false; selected = [] }
        for item in items {
            do {
                guard !Task.isCancelled, let data = try await item.loadTransferable(type: Data.self) else { return }
                let type = item.supportedContentTypes.first ?? .data
                let file = try await session.upload(data: data, name: "PUBO-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "bin")", mime: type.preferredMIMEType ?? "application/octet-stream")
                guard !file.id.isEmpty else { throw APIError.uncertain }
                draft.files.append(file); save()
            } catch { self.error = error.localizedDescription; draft.lastFailure = error.localizedDescription; save(); return }
        }
    }
    private func send() async {
        guard !busy, draft.outcome == "ready" else { return }
        busy = true; draft.outcome = "sending"; defer { busy = false }
        guard save() else { draft.outcome = "ready"; return }
        var body: [String: JSONValue] = ["visibility": .string(draft.visibility)]
        if !draft.files.isEmpty { body["fileIds"] = .strings(draft.files.map(\.id)) }
        if !draft.text.isEmpty { body["text"] = .string(draft.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if draft.useCW { body["cw"] = .string(draft.cw) }
        if let replyTo { body["replyId"] = .string(replyTo.id) }
        if let renote { body["renoteId"] = .string(renote.id) }
        do {
            let response = try await session.call("notes/create", body, mutation: true)
            guard NoteReceipt.matches(response, authorID: ownerID ?? "", request: body) else { throw APIError.uncertain }
            draft = ComposeDraft(); save(); onSent(); dismiss()
        } catch {
            draft.outcome = (error as? APIError)?.code == "OUTCOME_UNKNOWN" ? "uncertain" : "ready"
            self.error = error.localizedDescription; draft.lastFailure = error.localizedDescription; save()
        }
    }
}
