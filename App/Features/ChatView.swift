import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PUBOCore

struct ChatView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let peer: Record
    @State private var messages: [Record] = []
    @State private var pending: [PendingChat] = []
    @State private var text = ""
    @State private var attachments: [Record] = []
    @State private var reply: Record?
    @State private var error: String?
    @State private var busy = false
    @State private var loading = false
    @State private var hasMore = true
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var recorder = VoiceRecorder()
    @State private var restored = false
    @State private var ownerID: String?
    @State private var preview: PrivatePreviewItem?
    @State private var choosingEmoji = false
    @State private var choosingDrive = false
    @State private var actionMessage: Record?
    @State private var reporting = false
    @State private var confirmBlock = false
    @State private var syncEpoch = UUID()
    @State private var needsFullState = false
    private var outboxKey: String { "chat-outbox-" + peer.id }
    private var draftKey: String { "chat-draft-" + peer.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if hasMore { Button("更早的消息") { Task { await load(older: true) } }.disabled(loading) }
                    ForEach(messages) { message in bubble(message).id(message.id) }
                    ForEach(pending) { item in pendingBubble(item) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(16)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: pending.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }.safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .puboScreen().navigationTitle(peer.displayName)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) { HStack(spacing: 8) { Avatar(user: peer, size: 32); Text(peer.displayName).font(.headline).lineLimit(1) } }
                ToolbarItem(placement: .topBarTrailing) { Menu { Button("举报对方") { reporting = true }; Button("屏蔽对方", role: .destructive) { confirmBlock = true }; Link("在本站网页查看聊天", destination: Endpoint.origin.appendingPathComponent("chat/user/" + peer.id)) } label: { Image(systemName: "ellipsis") }.accessibilityLabel("聊天选项") }
            }
            .task {
                session.stream.showChat(peer.id)
                if !restored { restored = true; ownerID = session.user?.id; restore() }
                await load()
            }
            .task(id: session.streamRevision) { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { await load() } }
            .task(id: session.connectionRevision) { await load(reconcileAll: true) }
            .onChange(of: text) { _, _ in saveDraft() }
            .onChange(of: photos) { _, items in Task { await uploadPhotos(items) } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { recorder.cancel(); saveDraft() } else { Task { await load(reconcileAll: true) } } }
            .onDisappear { recorder.cancel(); saveDraft(); session.stream.showChat(nil) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in Task { await importFile(result) } }
            .sheet(isPresented: $choosingEmoji) { ReactionPicker { text += $0 } }
            .sheet(item: $preview) { item in PrivateAttachmentView(attachment: item.attachment) }
            .sheet(item: $actionMessage) { message in ChatMessageActions(message: message, peerID: peer.id) { updated in syncEpoch = UUID(); messages = ChatRecords.merge(messages, [updated]) } }
            .sheet(isPresented: $choosingDrive) { DrivePicker { file in Task { await importDrive(file) } } }
            .sheet(isPresented: $reporting) { ReportView(userID: peer.id, context: "私信会话：" + Endpoint.origin.appendingPathComponent("chat/user/" + peer.id).absoluteString) }
            .confirmationDialog("屏蔽对方后，将不能继续聊天。", isPresented: $confirmBlock) { Button("屏蔽对方", role: .destructive) { Task { do { _ = try await session.call("blocking/create", ["userId": .string(peer.id)], mutation: true); error = "已屏蔽对方" } catch { self.error = error.localizedDescription } } } }
    }
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("chat.error") }
            if let reply { HStack { Text("回复：" + reply.text).lineLimit(2); Spacer(); Button("取消回复") { self.reply = nil } }.font(.caption).padding(8).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8)) }
            if !attachments.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(attachments) { file in
                    HStack { Text(file["name"].string ?? "附件").lineLimit(1); Button { attachments.removeAll { $0.id == file.id }; saveDraft() } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("移除附件") }.font(.caption).padding(8).background(PUBOTheme.button, in: Capsule())
                } } }
            }
            TextField("在此输入信息", text: $text, axis: .vertical).lineLimit(1...5).padding(.vertical, 10).accessibilityIdentifier("chat.input")
            HStack(spacing: 6) {
                Menu {
                    Button("选择文件") { importing = true }
                    Button("从网盘导入") { choosingDrive = true }.disabled(attachments.count >= 10)
                    Button(recorder.recording ? "结束并添加语音" : "录制语音（最多60秒）") { Task { await voice() } }
                    if recorder.recording { Button("取消录音", role: .cancel) { recorder.cancel() } }
                } label: { Image(systemName: recorder.recording ? "mic.fill" : "paperclip").frame(width: 44, height: 44).foregroundStyle(recorder.recording ? .red : PUBOTheme.secondary) }.disabled(busy).accessibilityLabel("文件与语音")
                PhotosPicker(selection: $photos, maxSelectionCount: max(1, 10 - attachments.count), matching: .any(of: [.images, .videos])) { Image(systemName: "photo").frame(width: 44, height: 44) }.disabled(busy || attachments.count >= 10).accessibilityLabel("添加图片或视频")
                Button { choosingEmoji = true } label: { Image(systemName: "face.smiling").frame(width: 44, height: 44) }.accessibilityLabel("插入表情")
                Spacer(minLength: 0)
                Button { Task { await sendNew() } } label: {
                    Group { if busy { ProgressView() } else { Image(systemName: "paperplane").font(.title3) } }.frame(width: 44, height: 44).foregroundStyle(PUBOTheme.accent)
                }.disabled(busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)).accessibilityLabel("发送消息").accessibilityIdentifier("chat.send")
            }.buttonStyle(.borderless)
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            .background(PUBOTheme.panel).overlay(alignment: .top) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
    }
    private func bubble(_ message: Record) -> some View {
        let own = message["fromUserId"].string == session.user?.id
        return HStack(alignment: .top, spacing: 8) {
            if own { Spacer(minLength: 40) } else { Avatar(user: peer, size: 42) }
            VStack(alignment: own ? .trailing : .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 7) {
                    if !message["recalledAt"].isNull { Text("消息已撤回").foregroundStyle(PUBOTheme.secondary) }
                    else {
                        if let quoted = message["replyTo"]["text"].string { Text("回复：" + quoted).font(.caption).foregroundStyle(PUBOTheme.secondary).lineLimit(2).padding(6).background(PUBOTheme.divider.opacity(0.4), in: RoundedRectangle(cornerRadius: 6)) }
                        if !message.text.isEmpty { NoteText(text: message.text, expands: false) }
                        ForEach(Record.list(message["attachments"])) { file in Button { preview = PrivatePreviewItem(attachment: file, messageID: message.id) } label: { Label(file["kind"].string == "voice" ? "语音消息" : (file["name"].string ?? "附件"), systemImage: file["kind"].string == "voice" ? "waveform" : "paperclip") } }
                        if message["privateAttachmentFallback"].bool { Link("在本站网页查看此附件", destination: Endpoint.origin.appendingPathComponent("chat/messages/" + message.id)).font(.caption) }
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10)
                    .background(own ? PUBOTheme.ownBubble : PUBOTheme.panel, in: PUBOChatBubble(own: own))
                    .contextMenu {
                        if message["recalledAt"].isNull { Button("引用回复") { reply = message }; if !message.text.isEmpty { Button("复制文字") { UIPasteboard.general.string = message.text } } }
                        Button(own ? "编辑／撤回消息" : "消息反应／举报") { actionMessage = message }
                    }
                if !message["reactions"].array.isEmpty && message["recalledAt"].isNull {
                    Button { actionMessage = message } label: { Text(message["reactions"].array.compactMap { $0["reaction"].string }.joined(separator: " ")).font(.caption).padding(6).background(PUBOTheme.button, in: Capsule()) }.buttonStyle(.plain).accessibilityLabel("消息反应")
                }
                HStack(spacing: 6) {
                    if let date = puboDate(message["createdAt"].string) { Text(date, style: .time) }
                    if own { Text(message["readState"].string == "read" ? "已读" : "已发送") }
                    if !message["editedAt"].isNull { Text("已编辑") }
                }.font(.caption2).foregroundStyle(PUBOTheme.secondary)
            }.task { if !own && scenePhase == .active { await markRead(message) } }
            if !own { Spacer(minLength: 28) }
        }
    }
    private func pendingBubble(_ item: PendingChat) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(item.text.isEmpty ? "[附件]" : item.text).padding(.horizontal, 14).padding(.vertical, 10).background(PUBOTheme.ownBubble, in: PUBOChatBubble(own: true))
            Text(item.state == .uncertain ? APIError.uncertain.message : APIError.message(for: item.errorCode ?? "PENDING", status: 400)).font(.caption).foregroundStyle(PUBOTheme.secondary).multilineTextAlignment(.trailing).accessibilityIdentifier("chat.pending.error")
            ViewThatFits(in: .horizontal) {
                HStack { retryButton(item); removeButton(item) }
                VStack(alignment: .trailing) { retryButton(item); removeButton(item) }
            }.font(.caption)
        }.padding(.leading, 40).frame(maxWidth: .infinity, alignment: .trailing)
    }
    private func retryButton(_ item: PendingChat) -> some View {
        Button(item.state == .uncertain ? "核对发送结果" : "手动重试") { Task { await retry(item) } }.disabled(busy).frame(minHeight: 44).foregroundStyle(PUBOTheme.accent)
    }
    private func removeButton(_ item: PendingChat) -> some View {
        Button("移除待发") { pending.removeAll { $0.id == item.id }; persist() }.frame(minHeight: 44).foregroundStyle(PUBOTheme.accent)
    }
    private func restore() {
        guard let account = session.user?.id else { return }
        do {
            pending = OutboxRecovery.restore(try session.store?.read([PendingChat].self, account: account, key: outboxKey) ?? [])
            if let draft = try session.store?.read(ChatDraft.self, account: account, key: draftKey) { text = draft.text; attachments = draft.attachments; reply = draft.reply; error = draft.lastFailure }
            persist()
        } catch { self.error = "本机草稿读取失败，请先检查发送记录。" }
    }
    @discardableResult private func persist() -> Bool {
        guard let account = session.user?.id, account == ownerID else { return false }
        if session.testMode { return true }
        guard let store = session.store else { error = "本机存储不可用，暂时不能安全发送。"; return false }
        do { try store.save(pending, account: account, key: outboxKey); return true } catch { self.error = "待发记录保存失败，请不要退出页面。"; return false }
    }
    private func saveDraft() {
        guard restored, let account = session.user?.id, account == ownerID else { return }
        do { try session.store?.save(ChatDraft(text: text, attachments: attachments, reply: reply, lastFailure: error), account: account, key: draftKey) } catch { self.error = "草稿保存失败。" }
    }
    private func load(older: Bool = false, reconcileAll: Bool = false) async {
        if reconcileAll { needsFullState = true }
        guard !loading else { return }; loading = true; defer { loading = false }
        let epoch = syncEpoch
        do {
            var fields: [String: JSONValue] = ["userId": .string(peer.id), "limit": .number(50)]
            if older, let id = messages.first?.id { fields["untilId"] = .string(id) }
            let result = Record.list(try await session.call("chat/messages/user-timeline", fields))
            guard epoch == syncEpoch, !Task.isCancelled else { return }
            messages = Array(ChatRecords.merge(messages, result).suffix(2_000))
            if older || messages.count <= 50 { hasMore = result.count == 50 && messages.count < 2_000 }
            if let author = session.user?.id { pending.removeAll { item in result.contains { item.matches($0, authorID: author) } }; persist() }
            let all = needsFullState
            let ids = Array(Set((all ? messages.map(\.id) : []) + Array(session.changedChatIDs))).sorted()
            for offset in stride(from: 0, to: ids.count, by: 100) {
                let batch = Array(ids[offset..<min(offset + 100, ids.count)])
                let state = try await session.call("chat/messages/state", ["userId": .string(peer.id), "messageIds": .strings(batch)])
                guard epoch == syncEpoch, !Task.isCancelled else { return }
                guard case .array = state["messages"], case .array = state["missingIds"] else { throw APIError.invalidResponse }
                let updates = Record.list(state["messages"]).filter { batch.contains($0.id) }
                let missing = state["missingIds"].array.compactMap(\.string).filter { batch.contains($0) }
                messages = ChatRecords.merge(messages, updates, missingIDs: missing)
                session.changedChatIDs.subtract(batch)
                if let reply, missing.contains(reply.id) || updates.contains(where: { $0.id == reply.id && !$0["recalledAt"].isNull }) { self.reply = nil; saveDraft() }
                if let preview, missing.contains(preview.messageID) || updates.contains(where: { $0.id == preview.messageID && !$0["recalledAt"].isNull }) { self.preview = nil }
            }
            if all { needsFullState = false }
        } catch { self.error = error.localizedDescription }
    }
    private func sendNew() async {
        guard !busy else { return }
        let item = PendingChat(recipientID: peer.id, text: text, attachmentIDs: attachments.map(\.id), replyToID: reply?.id)
        pending.append(item)
        guard persist() else { pending.removeAll { $0.id == item.id }; return }
        text = ""; attachments = []; reply = nil; saveDraft()
        await send(item)
    }
    private func send(_ original: PendingChat) async {
        busy = true; defer { busy = false }
        guard let index = pending.firstIndex(where: { $0.id == original.id }) else { return }
        pending[index].state = .sending
        guard persist() else { pending[index].state = .ready; return }
        do {
            let result = Record(try await session.call("chat/messages/create-to-user", original.payload, mutation: true))
            guard !result.id.isEmpty, original.matches(result, authorID: session.user?.id ?? "") else { throw APIError.uncertain }
            syncEpoch = UUID(); messages = Array(ChatRecords.merge(messages, [result]).suffix(2_000))
            pending.removeAll { $0.id == original.id }; persist(); error = nil
        } catch {
            if let index = pending.firstIndex(where: { $0.id == original.id }) { pending[index].state = (error as? APIError)?.code == "OUTCOME_UNKNOWN" ? .uncertain : .rejected; pending[index].errorCode = (error as? APIError)?.code ?? "NETWORK_ERROR"; persist() }
        }
    }
    private func retry(_ item: PendingChat) async {
        guard !busy else { return }
        if item.state == .uncertain {
            busy = true
            do {
                // Scan from the attempt time so an older result is not missed on a busy conversation.
                var fields: [String: JSONValue] = ["userId": .string(peer.id), "limit": .number(100), "sinceDate": .number(floor(item.createdAt.addingTimeInterval(-5).timeIntervalSince1970 * 1000))]
                var found: Record?
                var complete = false
                for _ in 0..<10 {
                    let batch = Record.list(try await session.call("chat/messages/user-timeline", fields))
                    if let match = batch.first(where: { item.matches($0, authorID: session.user?.id ?? "") }) { found = match; break }
                    if batch.count < 100 { complete = true; break }
                    fields.removeValue(forKey: "sinceDate"); fields["sinceId"] = .string(batch.map(\.id).max()!)
                }
                if let found { syncEpoch = UUID(); messages = Array(ChatRecords.merge(messages, [found]).suffix(2_000)); pending.removeAll { $0.id == item.id }; persist(); busy = false; return }
                guard complete else { throw APIError.uncertain }
                // A complete fresh scan found no message. Same clientMessageId remains mandatory.
                busy = false; await send(item)
            } catch { self.error = error.localizedDescription; busy = false }
        } else { await send(item) }
    }
    private func markRead(_ message: Record) async {
        guard message["readState"].string != "read" else { return }
        do { _ = try await session.call("chat/messages/read", ["userId": .string(peer.id), "messageIds": .strings([message.id])], mutation: true) } catch { }
    }
    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        guard !busy else { return }; busy = true; defer { busy = false; photos = [] }
        for item in items {
            do {
                guard attachments.count < 10, let data = try await item.loadTransferable(type: Data.self) else { return }
                let type = item.supportedContentTypes.first ?? .data
                let file = try await session.upload(data: data, name: "PUBO-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "bin")", mime: type.preferredMIMEType ?? "application/octet-stream", peer: peer.id)
                attachments.append(file); saveDraft()
            } catch { self.error = error.localizedDescription; saveDraft(); return }
        }
    }
    private func importFile(_ result: Result<URL, Error>) async {
        guard !busy, attachments.count < 10 else { return }; busy = true; defer { busy = false }
        do {
            let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            attachments.append(try await session.upload(data: data, name: url.lastPathComponent, mime: type.preferredMIMEType ?? "application/octet-stream", peer: peer.id)); saveDraft()
        } catch { self.error = error.localizedDescription; saveDraft() }
    }
    private func importDrive(_ file: Record) async {
        guard !busy, attachments.count < 10 else { return }; busy = true; defer { busy = false }
        do {
            let value = Record(try await session.call("chat/attachments/import-drive", ["toUserId": .string(peer.id), "fileId": .string(file.id)], mutation: true))
            guard !value.id.isEmpty else { throw APIError.uncertain }
            attachments.append(value); saveDraft()
        } catch { self.error = error.localizedDescription; saveDraft() }
    }
    private func voice() async {
        guard !busy, attachments.count < 10 else { return }
        do {
            if recorder.recording { busy = true; defer { busy = false }; let data = try recorder.finish(); attachments.append(try await session.upload(data: data, name: "语音.m4a", mime: "audio/mp4", peer: peer.id, voice: true)); saveDraft() }
            else { try await recorder.start() }
        } catch { self.error = error.localizedDescription }
    }
}

struct ChatDraft: Codable { let text: String; let attachments: [Record]; var reply: Record?; var lastFailure: String? }
struct PrivatePreviewItem: Identifiable { var id: String { attachment.id }; let attachment: Record; let messageID: String }

struct PrivateAttachmentView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let attachment: Record
    @State private var data: Data?
    @State private var localURL: URL?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let error { ErrorBanner(message: error) }
                else if let data, attachment["mime"].string?.hasPrefix("image/") == true, let image = UIImage(data: data) { ScrollView { Image(uiImage: image).resizable().scaledToFit() } }
                else if let localURL, attachment["mime"].string?.hasPrefix("audio/") == true || attachment["mime"].string?.hasPrefix("video/") == true { MediaPlayer(url: localURL) }
                else if let localURL { ShareLink("保存或打开此文件", item: localURL) }
                else { ProgressView("正在验证附件权限…") }
            }.puboScreen().navigationTitle(attachment["name"].string ?? "私信附件").navigationBarTitleDisplayMode(.inline).toolbar { Button("关闭") { dismiss() } }
                .task {
                    do {
                        guard let token = session.token else { throw APIError.invalidResponse }
                        guard attachment["size"].int <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "附件超过首版 50 MB 预览上限，请在网页打开。") }
                        let epoch = session.generation
                        let content = try await session.api.privateAttachment(id: attachment.id, token: token)
                        guard epoch == session.generation, !Task.isCancelled else { return }
                        data = content
                        let ext = UTType(mimeType: attachment["mime"].string ?? "")?.preferredFilenameExtension ?? "bin"
                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pubo-private-\(UUID().uuidString).\(ext)")
                        try content.write(to: file, options: [.atomic, .completeFileProtection]); localURL = file
                    } catch { self.error = error.localizedDescription }
                }.onDisappear { data = nil; if let localURL { try? FileManager.default.removeItem(at: localURL) }; localURL = nil }
        }
    }
}

