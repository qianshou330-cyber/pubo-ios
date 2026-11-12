import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
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
    var localOnly: Bool?
    var visibleUsers: [Record]?
    var scheduledAt: Date?
}

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var replyTo: Record? = nil
    var renote: Record? = nil
    var channelID: String? = nil
    var embedded = false
    var onSent: () -> Void
    @State private var draft = ComposeDraft()
    @State private var textSelection = NSRange(location: 0, length: 0)
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
    @State private var choosingRecipient = false
    @State private var editingFile: Record?
    @State private var camera = false
    // UITextView owns focus; SwiftUI FocusState without a focused view resets after the first key.
    @State private var editingText = false
    private var key: String { "compose-" + (replyTo?.id ?? renote?.id ?? channelID ?? "new") }
    private var editable: Bool { restored && !busy && draft.outcome == "ready" }
    private var sendProblem: String? { SendFeedback.limitError(draft.text, limit: max(1, session.meta["maxNoteTextLength"].int > 0 ? session.meta["maxNoteTextLength"].int : 1000), label: "正文") ?? (draft.useCW ? SendFeedback.limitError(draft.cw, limit: 100, label: "内容提示") : nil) }
    private var canSend: Bool { editable && sendProblem == nil && (draft.visibility != "specified" || !(draft.visibleUsers ?? []).isEmpty) && (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.files.isEmpty || renote != nil || draft.poll != nil) }
    private var submitTitle: String { draft.scheduledAt != nil ? "定时发布" : replyTo != nil ? "回复" : renote != nil ? "引用" : "发帖" }
    private var submitIcon: String { replyTo != nil ? "arrowshape.turn.up.left" : renote != nil ? "quote.opening" : "paperplane" }
    private var visibilityTitle: String { draft.visibility == "specified" ? "指定用户" : draft.visibility == "home" ? "首页" : draft.visibility == "followers" ? "关注者" : "公开" }
    private var visibilityChoices: [String] { ComposePrivacy.allowedVisibilities(reply: replyTo, channelID: channelID, silenced: session.user?["isSilenced"].bool ?? false) }
    private var visibilitySelection: Binding<String> { Binding(get: { draft.visibility }, set: { draft.visibility = $0; applyPrivacy(); save() }) }
    private var visibilityIcon: String { draft.visibility == "home" ? "house" : draft.visibility == "followers" ? "lock" : draft.visibility == "specified" ? "envelope" : "globe" }

    var body: some View {
        Group { if embedded { editor.frame(height: 340) } else { NavigationStack { editor } } }.interactiveDismissDisabled(busy)
    }
    private var editor: some View {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let replyTo { contextNote(replyTo, title: "回复 \(replyTo.user.displayName)") }
                        if let renote { contextNote(renote, title: "引用转发") }
                        if channelID != nil { Text("此帖发布到所选频道；频道帖子使用公开可见范围，仅本站发布。").font(.caption) }
                        if draft.useCW {
                            TextField("内容提示", text: $draft.cw).font(.subheadline).padding(.vertical, 10)
                                .overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 1) }
                                .disabled(!editable).accessibilityIdentifier("compose.cw")
                        }
                        CursorTextEditor(text: $draft.text, selection: $textSelection, focused: Binding(get: { editingText }, set: { editingText = $0 }), enabled: editable, identifier: "compose.text", placeholder: "有什么新鲜事？", minimumHeight: typeSize.isAccessibilitySize ? 210 : 160, maximumHeight: typeSize.isAccessibilitySize ? 350 : 260)
                            .frame(minHeight: typeSize.isAccessibilitySize ? 210 : 160)
                            .overlay(alignment: .topLeading) {
                                if draft.text.isEmpty { Text(replyTo != nil ? "写下你的回复…" : "有什么新鲜事？").font(.subheadline).foregroundStyle(PUBOTheme.secondary.opacity(0.65)).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true) }
                            }.disabled(!editable)
                        if let sendProblem { Text(sendProblem).font(.caption).foregroundStyle(.red).accessibilityIdentifier("compose.limit") }
                        if editable { ComposeSuggestions(text: $draft.text) }
                        if let replyTo, replyTo["visibility"].string != "public" {
                            Text("回复不会扩大原帖的可见范围；可以选择更严格的范围。").font(.caption).foregroundStyle(PUBOTheme.secondary)
                        }
                        if draft.visibility == "specified" {
                            ForEach(draft.visibleUsers ?? []) { user in HStack { Text(user.displayName); Spacer(); Button("移除") { draft.visibleUsers?.removeAll { $0.id == user.id }; save() } } }
                            Button("添加可见用户") { choosingRecipient = true }.disabled(!editable)
                        }
                        if draft.scheduledAt != nil {
                            DatePicker("发布时间", selection: Binding(get: { draft.scheduledAt ?? Date().addingTimeInterval(3600) }, set: { draft.scheduledAt = $0; save() }), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            Text("由 PUBO 服务器定时发布，关闭 App 后仍可执行。").font(.caption)
                            Button("取消定时") { draft.scheduledAt = nil; save() }
                        }
                        ForEach(draft.files) { file in
                            HStack { Image(systemName: "paperclip"); Text(file["name"].string ?? "已上传附件").lineLimit(2); Spacer(); Button("设置") { editingFile = file }; Button("移除") { draft.files.removeAll { $0.id == file.id }; save() } }
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
                                if draft.scheduledAt != nil { NavigationLink("核对定时帖子") { ScheduledNotesView() } }
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
                    var hasSavedDraft = false
                    if let account = session.user?.id, let saved = try? session.store?.read(ComposeDraft.self, account: account, key: key) { hasSavedDraft = true; draft = saved; error = saved.lastFailure; if draft.outcome == "sending" { draft.outcome = "uncertain" } }
                    applyPrivacy(seedReplyRecipients: !hasSavedDraft)
                    save()
                    await resolveRecipientNames()
                }
                .onChange(of: draft.text) { _, _ in save() }
                .onChange(of: draft.cw) { _, _ in save() }
                .onChange(of: draft.visibility) { _, _ in save() }
                .onChange(of: draft.useCW) { _, _ in save() }
                .onChange(of: selected) { _, values in uploadTask = Task { await upload(values) } }
                .onDisappear { uploadTask?.cancel() }
                .sheet(isPresented: $choosingEmoji) { ReactionPicker { TextInsertion.insert($0, into: &draft.text, selection: &textSelection) }.environment(\.dynamicTypeSize, typeSize) }
                .sheet(isPresented: $choosingDrive) { DrivePicker { file in if draft.files.count < 16 && !draft.files.contains(where: { $0.id == file.id }) { draft.files.append(file); save() } }.environment(\.dynamicTypeSize, typeSize) }
                .sheet(isPresented: $choosingRecipient) { UserPicker { user in
                    if replyTo?["visibility"].string == "specified", !ComposePrivacy.replyRecipientIDs(replyTo, accountID: ownerID ?? "").contains(user.id) {
                        error = "此回复只能选择原帖的可见用户。"; return
                    }
                    if !(draft.visibleUsers ?? []).contains(where: { $0.id == user.id }) { draft.visibleUsers = (draft.visibleUsers ?? []) + [user]; applyPrivacy(); save() }
                } }
                .sheet(item: $editingFile) { file in AttachmentMetadataEditor(file: file) { current in draft.files = draft.files.map { $0.id == current.id ? current : $0 }; save() } }
                .fullScreenCover(isPresented: $camera) { CameraCapture { result in camera = false; uploadTask = Task { await uploadCapture(result) } }.ignoresSafeArea() }
                .photosPicker(isPresented: $showingPhotoPicker, selection: $selected, maxSelectionCount: max(1, 16 - draft.files.count), matching: .any(of: [.images, .videos]))
                .confirmationDialog("只有确认原帖未发布时才重新提交，否则可能产生重复帖子。", isPresented: $confirmRetry) { Button("确认恢复手动提交") { draft.outcome = "ready"; save() } }
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            HStack(spacing: 6) {
                Button { if save() && !embedded { dismiss() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("保存并关闭").accessibilityIdentifier("compose.close").disabled(busy).opacity(embedded ? 0 : 1).allowsHitTesting(!embedded)
                if let user = session.user { Avatar(user: user, size: 28).accessibilityHidden(false).accessibilityLabel(user.displayName) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Menu {
                    Picker("可见范围", selection: visibilitySelection) {
                        ForEach(visibilityChoices, id: \.self) { scope in
                            Text(["public": "公开", "home": "首页", "followers": "关注者", "specified": "指定用户"][scope] ?? scope).tag(scope)
                        }
                    }
                    if draft.visibility != "specified" {
                        Toggle("仅本站发布", isOn: Binding(get: { draft.localOnly ?? false }, set: { draft.localOnly = $0; applyPrivacy(); save() }))
                    }
                } label: { Image(systemName: visibilityIcon).frame(width: 44, height: 44) }
                    .disabled(!editable || channelID != nil).accessibilityLabel("可见范围").accessibilityValue(visibilityTitle).accessibilityIdentifier("compose.visibility")
                Menu {
                    Toggle("预览", isOn: $showingPreview)
                    Button("从网盘选择") { choosingDrive = true }.disabled(!editable || draft.files.count >= 16)
                    Button("添加投票") { draft.poll = PollDraft(); save() }.disabled(!editable || draft.poll != nil)
                    Button("拍摄照片或视频") { Task { await openCamera() } }.disabled(!editable || draft.files.count >= 16)
                    Button("定时发布") { draft.scheduledAt = Date().addingTimeInterval(3600); save() }.disabled(!editable || (session.user?["policies"]["scheduledNoteLimit"].int ?? 0) <= 0)
                    if !embedded { Button("保存并关闭") { if save() { dismiss() } } }
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
            Button { TextInsertion.insert(" #", into: &draft.text, selection: &textSelection); editingText = true } label: { Image(systemName: "number").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(!editable).accessibilityLabel("插入话题")
            Button { TextInsertion.insert(" @", into: &draft.text, selection: &textSelection); editingText = true } label: { Image(systemName: "at").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(!editable).accessibilityLabel("插入提及")
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
    private func applyPrivacy(seedReplyRecipients: Bool = false) {
        let selection = ComposePrivacy.resolve(visibility: draft.visibility, localOnly: draft.localOnly ?? false,
            recipientIDs: (draft.visibleUsers ?? []).map(\.id), reply: replyTo, channelID: channelID,
            accountID: ownerID ?? session.user?.id ?? "", seedReplyRecipients: seedReplyRecipients,
            silenced: session.user?["isSilenced"].bool ?? false)
        let known = Dictionary((draft.visibleUsers ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        draft.visibility = selection.visibility; draft.localOnly = selection.localOnly
        draft.visibleUsers = selection.recipientIDs.map { id in
            if let user = known[id] { return user }
            if let author = replyTo?.user, author.id == id { return author }
            return Record(.object(["id": .string(id), "name": .string("用户 " + id)]))
        }
    }
    private func resolveRecipientNames() async {
        let ids = (draft.visibleUsers ?? []).map(\.id)
        guard !ids.isEmpty, let ownerID else { return }
        do {
            let users = Record.list(try await session.call("users/show", ["userIds": .strings(ids)]))
            try Task.checkCancellation()
            guard ownerID == session.user?.id else { return }
            let known = Dictionary(users.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // A delayed lookup must not re-add recipients removed while it ran.
            draft.visibleUsers = (draft.visibleUsers ?? []).map { known[$0.id] ?? $0 }; save()
        } catch { /* IDs remain explicit and valid even if display-name lookup fails. */ }
    }
    @discardableResult private func save() -> Bool {
        guard restored, let account = session.user?.id, account == ownerID else { return false }
        if session.testMode {
            #if DEBUG
            guard !session.isolatedBackend && ProcessInfo.processInfo.arguments.contains("--four-tabs-drafts") else { return true }
            #else
            return true
            #endif
        }
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
        applyPrivacy()
        if draft.visibility == "specified" && (draft.visibleUsers ?? []).isEmpty { error = "请至少选择一位可见用户。"; return }
        if let sendProblem { error = sendProblem; return }
        let poll: JSONValue?
        do {
            poll = try draft.poll?.request()
            if let date = draft.scheduledAt, date <= Date() { throw APIError(code: "INVALID_SCHEDULE", message: "请选择未来的发布时间。") }
        } catch { self.error = error.localizedDescription; return }
        busy = true; draft.outcome = "sending"; defer { busy = false }
        guard save() else { draft.outcome = "ready"; return }
        var body: [String: JSONValue] = ["visibility": .string(draft.visibility)]
        if let channelID {
            guard draft.visibility == "public" else { draft.outcome = "ready"; save(); error = "频道发帖需要选择公开可见范围。"; return }
            body["channelId"] = .string(channelID)
        }
        body["localOnly"] = .bool(draft.localOnly ?? false)
        if draft.visibility == "specified" { body["visibleUserIds"] = .strings((draft.visibleUsers ?? []).map(\.id)) }
        if let poll { body["poll"] = poll }
        if !draft.files.isEmpty { body["fileIds"] = .strings(draft.files.map(\.id)) }
        if !draft.text.isEmpty { body["text"] = .string(draft.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if draft.useCW { body["cw"] = .string(draft.cw) }
        if let replyTo { body["replyId"] = .string(replyTo.id) }
        if let renote { body["renoteId"] = .string(renote.id) }
        if let date = draft.scheduledAt { body["scheduledAt"] = .number(floor(date.timeIntervalSince1970 * 1000)); body["isActuallyScheduled"] = .bool(true) }
        do {
            let scheduled = draft.scheduledAt != nil
            let response = try await session.call(scheduled ? "notes/drafts/create" : "notes/create", body, mutation: true)
            if scheduled {
                guard response["createdDraft"]["scheduledAt"] == body["scheduledAt"], response["createdDraft"]["isActuallyScheduled"].bool,
                      NoteReceipt.matches(.object(["createdNote": response["createdDraft"]]), authorID: ownerID ?? "", request: body) else { throw APIError.uncertain }
            } else { guard NoteReceipt.matches(response, authorID: ownerID ?? "", request: body) else { throw APIError.uncertain } }
            draft = ComposeDraft(); save(); onSent(); if !embedded { dismiss() }
        } catch {
            draft.outcome = (error as? APIError)?.code == "OUTCOME_UNKNOWN" ? "uncertain" : "ready"
            self.error = error.localizedDescription; draft.lastFailure = error.localizedDescription; save()
        }
    }
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = "当前设备没有可用相机。"; return }
        let owner = session.generation
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard owner == session.generation, !Task.isCancelled else { return }
        if allowed { camera = true } else { error = "未获得相机权限，仍可从相册或网盘选择媒体。" }
    }
    private func uploadCapture(_ result: Result<(Data, String, String), Error>) async {
        guard editable, ownerID == session.user?.id else { return }; busy = true; defer { busy = false }
        do { let (data, name, mime) = try result.get(); let file = try await session.upload(data: data, name: name, mime: mime); try Task.checkCancellation(); draft.files.append(file); save() }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

