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
    private var outboxKey: String { "chat-outbox-" + peer.id }
    private var draftKey: String { "chat-draft-" + peer.id }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if hasMore { Button("更早的消息") { Task { await load(older: true) } }.disabled(loading) }
                        ForEach(messages) { message in bubble(message).id(message.id) }
                        ForEach(pending) { item in pendingBubble(item) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding()
                }.onChange(of: messages.last?.id) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal).accessibilityIdentifier("chat.error") }
            if let reply { HStack { Text("回复：" + reply.text).lineLimit(1); Spacer(); Button("取消回复") { self.reply = nil } }.font(.caption).padding(.horizontal) }
            if !attachments.isEmpty { ScrollView(.horizontal) { HStack { ForEach(attachments) { file in HStack { Text(file["name"].string ?? "附件").lineLimit(1); Button { attachments.removeAll { $0.id == file.id }; saveDraft() } label: { Image(systemName: "xmark.circle") } }.font(.caption).padding(6).background(.quaternary, in: Capsule()) } } }.padding(.horizontal) }
            HStack(alignment: .bottom) {
                Menu {
                    Button("选择文件") { importing = true }
                    Button(recorder.recording ? "结束并添加语音" : "录制语音（最多60秒）") { Task { await voice() } }
                    if recorder.recording { Button("取消录音", role: .cancel) { recorder.cancel() } }
                } label: { Image(systemName: recorder.recording ? "mic.fill" : "plus.circle").font(.title2).foregroundStyle(recorder.recording ? .red : .primary) }.disabled(busy)
                PhotosPicker(selection: $photos, maxSelectionCount: max(1, 10 - attachments.count), matching: .any(of: [.images, .videos])) { Image(systemName: "photo").font(.title2) }.disabled(busy || attachments.count >= 10)
                TextField("发送消息", text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).accessibilityIdentifier("chat.input")
                Button { Task { await sendNew() } } label: { if busy { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title) } }.disabled(busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)).accessibilityLabel("发送消息").accessibilityIdentifier("chat.send")
            }.padding().background(.bar)
        }.navigationTitle(peer.displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar { Menu { Link("在本站网页查看聊天", destination: Endpoint.origin.appendingPathComponent("chat/user/" + peer.id)) } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("聊天选项") }
            .task {
                session.stream.showChat(peer.id)
                if !restored { restored = true; ownerID = session.user?.id; restore() }
                await load()
            }
            .task(id: session.streamRevision) { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { await load() } }
            .onChange(of: text) { _, _ in saveDraft() }
            .onChange(of: photos) { _, items in Task { await uploadPhotos(items) } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { recorder.cancel(); saveDraft() } else { Task { await load() } } }
            .onDisappear { recorder.cancel(); saveDraft(); session.stream.showChat(nil) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in Task { await importFile(result) } }
            .sheet(item: $preview) { item in PrivateAttachmentView(attachment: item.attachment) }
    }
    private func bubble(_ message: Record) -> some View {
        let own = message["fromUserId"].string == session.user?.id
        return HStack {
            if own { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 7) {
                if !message["recalledAt"].isNull { Text("消息已撤回").foregroundStyle(.secondary) }
                else {
                    if let quoted = message["replyTo"]["text"].string { Text("回复：" + quoted).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if !message.text.isEmpty { NoteText(text: message.text) }
                    ForEach(Record.list(message["attachments"])) { file in Button { preview = PrivatePreviewItem(attachment: file) } label: { Label(file["kind"].string == "voice" ? "语音消息" : (file["name"].string ?? "附件"), systemImage: file["kind"].string == "voice" ? "waveform" : "paperclip") } }
                    if message["privateAttachmentFallback"].bool { Link("在本站网页查看此附件", destination: Endpoint.origin.appendingPathComponent("chat/messages/" + message.id)).font(.caption) }
                }
                if own { Text(message["readState"].string == "read" ? "已读" : "已发送").font(.caption2).foregroundStyle(.secondary) }
            }.padding(12).background(own ? Color.green.opacity(0.17) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .contextMenu { Button("引用回复") { reply = message }; if !message.text.isEmpty { Button("复制文字") { UIPasteboard.general.string = message.text } } }
                .task { if !own && scenePhase == .active { await markRead(message) } }
            if !own { Spacer(minLength: 40) }
        }
    }
    private func pendingBubble(_ item: PendingChat) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(item.text.isEmpty ? "[附件]" : item.text).padding(12).background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            Text(item.state == .uncertain ? APIError.uncertain.message : APIError.message(for: item.errorCode ?? "PENDING", status: 400)).font(.caption).foregroundStyle(.red).accessibilityIdentifier("chat.pending.error")
            HStack { Spacer(); Button(item.state == .uncertain ? "核对发送结果" : "手动重试") { Task { await retry(item) } }.disabled(busy); Button("移除待发") { pending.removeAll { $0.id == item.id }; persist() } }.font(.caption)
        }.frame(maxWidth: .infinity, alignment: .trailing)
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
    private func load(older: Bool = false) async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            var fields: [String: JSONValue] = ["userId": .string(peer.id), "limit": .number(50)]
            if older, let id = messages.first?.id { fields["untilId"] = .string(id) }
            let result = Record.list(try await session.call("chat/messages/user-timeline", fields))
            messages = Records.merge(messages, result, newestFirst: false, limit: 2_000)
            if older || messages.count <= 50 { hasMore = result.count == 50 && messages.count < 2_000 }
            if let author = session.user?.id { pending.removeAll { item in result.contains { item.matches($0, authorID: author) } }; persist() }
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
            messages = Records.merge(messages, [result], newestFirst: false, limit: 2_000)
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
                if let found { messages = Records.merge(messages, [found], newestFirst: false, limit: 2_000); pending.removeAll { $0.id == item.id }; persist(); busy = false; return }
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
    private func voice() async {
        guard !busy, attachments.count < 10 else { return }
        do {
            if recorder.recording { busy = true; defer { busy = false }; let data = try recorder.finish(); attachments.append(try await session.upload(data: data, name: "语音.m4a", mime: "audio/mp4", peer: peer.id, voice: true)); saveDraft() }
            else { try await recorder.start() }
        } catch { self.error = error.localizedDescription }
    }
}

struct ChatDraft: Codable { let text: String; let attachments: [Record]; var reply: Record?; var lastFailure: String? }
struct PrivatePreviewItem: Identifiable { var id: String { attachment.id }; let attachment: Record }

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
            }.navigationTitle(attachment["name"].string ?? "私信附件").navigationBarTitleDisplayMode(.inline).toolbar { Button("关闭") { dismiss() } }
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
