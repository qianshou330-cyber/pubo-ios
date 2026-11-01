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
    var poll: PollDraft?
}

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var replyTo: Record? = nil
    var renote: Record? = nil
    var onSent: () -> Void
    @State private var draft = ComposeDraft()
    @State private var selected: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var busy = false
    @State private var error: String?
    @State private var restored = false
    @State private var ownerID: String?
    @State private var confirmRetry = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var choosingEmoji = false
    @State private var showingPreview = false
    @State private var choosingDrive = false
    @FocusState private var editingText: Bool
    private var key: String { "compose-" + (replyTo?.id ?? renote?.id ?? "new") }
    private var editable: Bool { !busy && draft.outcome == "ready" }
    private var canSend: Bool { editable && (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.files.isEmpty || renote != nil || draft.poll != nil) }
    private var submitTitle: String { replyTo != nil ? "回复" : renote != nil ? "引用" : "发帖" }
    private var submitIcon: String { replyTo != nil ? "arrowshape.turn.up.left" : renote != nil ? "quote.opening" : "paperplane" }
    private var visibilityTitle: String { draft.visibility == "home" ? "首页" : draft.visibility == "followers" ? "关注者" : "公开" }
    private var visibilityIcon: String { draft.visibility == "home" ? "house" : draft.visibility == "followers" ? "lock" : "globe" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let replyTo { contextNote(replyTo, title: "回复 \(replyTo.user.displayName)") }
                        if let renote { contextNote(renote, title: "引用转发") }
                        if draft.useCW {
                            TextField("内容提示", text: $draft.cw).font(.subheadline).padding(.vertical, 10)
                                .overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 1) }
                                .disabled(!editable).accessibilityIdentifier("compose.cw")
                        }
                        TextEditor(text: $draft.text).font(.subheadline).scrollContentBackground(.hidden)
                            .frame(minHeight: typeSize.isAccessibilitySize ? 210 : 160)
                            .overlay(alignment: .topLeading) {
                                if draft.text.isEmpty { Text(replyTo != nil ? "写下你的回复…" : "有什么新鲜事？").font(.subheadline).foregroundStyle(PUBOTheme.secondary.opacity(0.65)).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true) }
                            }.focused($editingText).disabled(!editable).accessibilityIdentifier("compose.text")
                        ForEach(draft.files) { file in
                            HStack { Image(systemName: "paperclip"); Text(file["name"].string ?? "已上传附件").lineLimit(2); Spacer(); Button("移除") { draft.files.removeAll { $0.id == file.id }; save() } }
                                .font(.subheadline).padding(10).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8)).disabled(!editable)
                        }
                        if draft.poll != nil {
                            PollEditor(draft: Binding(get: { draft.poll ?? PollDraft() }, set: { draft.poll = $0; save() })).disabled(!editable)
                            Button("移除投票", role: .destructive) { draft.poll = nil; save() }.disabled(!editable)
                        }
                        if !typeSize.isAccessibilitySize { editorTools }
                        if showingPreview { preview }
                        if let error { Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("compose.error") }
                        if draft.outcome != "ready" {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("发送结果待确认").font(.headline)
                                Text("请先检查自己的帖子。此接口不能保证重复提交只产生一条帖子，客户端不会自动重发。")
                                if let user = session.user { NavigationLink("查看我的帖子") { ProfileView(userID: user.id) } }
                                Button("已核对记录，恢复手动提交") { confirmRetry = true }
                            }.font(.callout).padding(12).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 20)
                }.scrollDismissesKeyboard(.interactively)
            }.safeAreaInset(edge: .bottom, spacing: 0) {
                if typeSize.isAccessibilitySize { editorTools.padding(.horizontal, 16).background(PUBOTheme.panel) }
            }.background(PUBOTheme.panel.ignoresSafeArea()).foregroundStyle(PUBOTheme.text)
                .toolbar(.hidden, for: .navigationBar)
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
                .sheet(isPresented: $choosingEmoji) { ReactionPicker { draft.text += $0 }.environment(\.dynamicTypeSize, typeSize) }
                .sheet(isPresented: $choosingDrive) { DrivePicker { file in if draft.files.count < 16 && !draft.files.contains(where: { $0.id == file.id }) { draft.files.append(file); save() } }.environment(\.dynamicTypeSize, typeSize) }
                .photosPicker(isPresented: $showingPhotoPicker, selection: $selected, maxSelectionCount: max(1, 16 - draft.files.count), matching: .any(of: [.images, .videos]))
                .confirmationDialog("只有确认原帖未发布时才重新提交，否则可能产生重复帖子。", isPresented: $confirmRetry) { Button("确认恢复手动提交") { draft.outcome = "ready"; save() } }
        }.interactiveDismissDisabled(busy)
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            HStack(spacing: 6) {
                Button { if save() { dismiss() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("保存并关闭").accessibilityIdentifier("compose.close").disabled(busy)
                if let user = session.user { Avatar(user: user, size: 28).accessibilityHidden(false).accessibilityLabel(user.displayName) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Menu {
                    Picker("可见范围", selection: $draft.visibility) { Text("公开").tag("public"); Text("首页").tag("home"); Text("关注者").tag("followers") }
                } label: { Image(systemName: visibilityIcon).frame(width: 44, height: 44) }
                    .disabled(!editable).accessibilityLabel("可见范围").accessibilityValue(visibilityTitle).accessibilityIdentifier("compose.visibility")
                Menu {
                    Toggle("预览", isOn: $showingPreview)
                    Button("从网盘选择") { choosingDrive = true }.disabled(!editable || draft.files.count >= 16)
                    Button("添加投票") { draft.poll = PollDraft(); save() }.disabled(!editable || draft.poll != nil)
                    Button("保存并关闭") { if save() { dismiss() } }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .disabled(busy).accessibilityLabel("更多").accessibilityIdentifier("compose.more")
                Button { editingText = false; Task { await send() } } label: {
                    HStack(spacing: 6) { Text(submitTitle); Image(systemName: submitIcon) }
                }.buttonStyle(PUBOPostButtonStyle(submit: true)).disabled(!canSend).accessibilityLabel(submitTitle).accessibilityIdentifier("compose.send")
            }
        }.buttonStyle(.plain).font(.subheadline).padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var editorTools: some View {
        HStack(spacing: 0) {
            Button { showingPhotoPicker = true } label: {
                Image(systemName: "photo.badge.plus").frame(width: 44, height: 44).contentShape(Rectangle())
            }.disabled(!editable || draft.files.count >= 16).accessibilityLabel("添加图片或视频")
            Button { draft.useCW.toggle() } label: { Image(systemName: "eye.slash").frame(width: 44, height: 44).contentShape(Rectangle()).foregroundStyle(draft.useCW ? PUBOTheme.accent : PUBOTheme.secondary) }
                .disabled(!editable).accessibilityLabel("内容警告").accessibilityValue(draft.useCW ? "已开启" : "已关闭").accessibilityIdentifier("compose.toggleCW")
            Button { draft.text += " #"; editingText = true } label: { Image(systemName: "number").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(!editable).accessibilityLabel("插入话题")
            Button { draft.text += " @"; editingText = true } label: { Image(systemName: "at").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(!editable).accessibilityLabel("插入提及")
            Spacer(minLength: 0)
            if editingText { Button { editingText = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("收起键盘") }
            Button { choosingEmoji = true } label: { Image(systemName: "face.smiling").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(!editable).accessibilityLabel("插入表情")
        }.font(.system(size: 20)).buttonStyle(.plain).foregroundStyle(PUBOTheme.secondary)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预览").font(.caption).foregroundStyle(PUBOTheme.secondary)
            if let user = session.user { HStack { Avatar(user: user, size: 28); Text(user.displayName).font(.subheadline.weight(.semibold)) } }
            if draft.useCW { Label(draft.cw.isEmpty ? "内容警告" : draft.cw, systemImage: "eye.slash").font(.subheadline) }
            else { NoteText(text: draft.text).font(.subheadline) }
            if !draft.files.isEmpty { Text("\(draft.files.count) 个附件").font(.caption) }
            if let poll = draft.poll { Text("投票 · \(poll.choices.count) 个选项").font(.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8))
    }

    private func contextNote(_ note: Record, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(PUBOTheme.secondary); Text(note["cw"].string ?? note.text).font(.subheadline).lineLimit(3) }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8))
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
        let poll: JSONValue?
        do { poll = try draft.poll?.request() } catch { self.error = error.localizedDescription; return }
        busy = true; draft.outcome = "sending"; defer { busy = false }
        guard save() else { draft.outcome = "ready"; return }
        var body: [String: JSONValue] = ["visibility": .string(draft.visibility)]
        if let poll { body["poll"] = poll }
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

