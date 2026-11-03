import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PUBOCore

private struct RoomDraft: Codable {
    var text = ""
    var file: Record?
    var pending = false
}

struct RoomChatView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let roomID: String
    @State private var room: Record?
    @State private var messages: [Record] = []
    @State private var draft = RoomDraft()
    @State private var ownerID: String?
    @State private var error: String?
    @State private var busy = false
    @State private var loading = false
    @State private var hasMore = false
    @State private var active = false
    @State private var restored = false
    @State private var choosingFile = false
    @State private var importingFile = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var choosingEmoji = false
    @State private var showingInfo = false
    @State private var textSelection = NSRange(location: 0, length: 0)
    @State private var nearBottom = true
    @State private var unreadBelow = false
    @State private var scrollRequest = 0
    @State private var uploadTask: Task<Void, Never>?
    private var sendProblem: String? { SendFeedback.limitError(draft.text, limit: 2000) }
    @State private var preview: Record?
    @State private var editing = false
    @State private var operation: String?
    @State private var reactionTarget: Record?
    @State private var deletingMessage: Record?
    private var own: Bool { room?["ownerId"].string == session.user?.id }
    private var invited: Bool { room?["invitationExists"].bool ?? false }
    private var key: String { "room-draft-" + roomID }
    private var canSend: Bool { !draft.pending && !busy && sendProblem == nil && room != nil && !invited && (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.file != nil) }

    private var timeline: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if hasMore { Button("更早的群聊消息") { Task { await load(older: true) } }.disabled(loading) }
                        ForEach(messages) { message in messageRow(message).id(message.id) }
                        Color.clear.frame(height: 1).id("bottom").background(GeometryReader { geo in Color.clear.preference(key: ChatBottomPreference.self, value: geo.frame(in: .named("roomScroll")).maxY) })
                    }.padding(16)
                }.coordinateSpace(name: "roomScroll").scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(ChatBottomPreference.self) { bottom in nearBottom = bottom <= viewport.size.height + 80; if nearBottom { unreadBelow = false } }
                    .onChange(of: messages.last?.id) { old, _ in if old == nil || nearBottom { proxy.scrollTo("bottom", anchor: .bottom) } else { unreadBelow = true } }
                    .onChange(of: scrollRequest) { _, _ in proxy.scrollTo("bottom", anchor: .bottom); unreadBelow = false }
            }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if unreadBelow { Button("有新消息 · 回到最新") { scrollRequest += 1 }.frame(minHeight: 44) }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("room.error") }
            if let sendProblem { Text(sendProblem).font(.caption).foregroundStyle(.red).accessibilityIdentifier("room.limit") }
            if draft.pending {
                Text("发送结果待核对。请检查本群最新消息；不会自动重发。").font(.caption)
                HStack {
                    Button("核对最新消息") { Task { await load() } }.disabled(loading)
                    Menu("核对后处理") {
                        Button("已发出，清空待发内容") { draft = RoomDraft(); persist() }
                        Button("确认未发出，恢复编辑") { draft.pending = false; persist() }
                    }
                }
            }
            if let file = draft.file { HStack { Text(file["name"].string ?? "附件").lineLimit(1); Button("移除附件") { draft.file = nil; persist() }.disabled(busy || draft.pending) } }
            CursorTextEditor(text: $draft.text, selection: $textSelection, enabled: !busy && !draft.pending, identifier: "room.input", placeholder: "群聊消息")
                .overlay(alignment: .topLeading) { if draft.text.isEmpty { Text("群聊消息").font(.subheadline).foregroundStyle(PUBOTheme.secondary.opacity(0.65)).padding(.top, 8).allowsHitTesting(false) } }
            HStack(spacing: 4) {
                Menu {
                    Button("从网盘选择") { choosingFile = true }
                    Button("选择本地文件") { importingFile = true }
                    Button("选择图片或视频") { choosingPhoto = true }
                } label: { Image(systemName: "paperclip").frame(width: 44, height: 44) }.disabled(busy || draft.pending).accessibilityLabel("添加群聊附件")
                Button { choosingPhoto = true } label: { Image(systemName: "photo").frame(width: 44, height: 44) }.disabled(busy || draft.pending).accessibilityLabel("群聊图片或视频")
                Button { choosingEmoji = true } label: { Image(systemName: "face.smiling").frame(width: 44, height: 44) }.disabled(busy || draft.pending).accessibilityLabel("插入群聊表情")
                Spacer(minLength: 0)
                Button { Task { await send() } } label: { Group { if busy { ProgressView() } else { Image(systemName: "paperplane").font(.title3) } }.frame(width: 44, height: 44) }.disabled(!canSend).accessibilityLabel("发送").accessibilityIdentifier("room.send")
            }.buttonStyle(.borderless)
        }.padding().background(PUBOTheme.panel)
    }
    private var roomContent: some View {
        Group {
            if invited {
                VStack(spacing: 20) { Text("你受邀加入此群聊"); Text(room?["name"].string ?? "").font(.headline); Button("接受邀请并加入") { Task { await perform("join") } }; Button("忽略邀请") { operation = "invitations/ignore" } }.padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        NavigationLink { RoomMembersView(roomID: roomID, canInvite: own) } label: { Label("成员", systemImage: "person.2").frame(maxWidth: .infinity, minHeight: 44) }
                        NavigationLink { ChatSearchView(roomID: roomID) } label: { Label("搜索", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 44) }
                        Button { showingInfo = true } label: { Label("关于", systemImage: "info.circle").frame(maxWidth: .infinity, minHeight: 44) }
                    }.font(.subheadline).background(PUBOTheme.panel)
                    timeline
                }.safeAreaInset(edge: .bottom, spacing: 0) { composer }
            }
        }.navigationTitle(room?["name"].string ?? "群聊").puboScreen().toolbar(.hidden, for: .tabBar)
            .toolbar {
                if room != nil && !invited {
                    Menu {
                        NavigationLink("群聊成员") { RoomMembersView(roomID: roomID, canInvite: own) }
                        NavigationLink("搜索本群") { ChatSearchView(roomID: roomID) }
                        if !own { Button(room?["isMuted"].bool == true ? "恢复提醒" : "免打扰") { Task { await mute() } } }
                        if own { Button("修改群聊") { editing = true }; Button("删除群聊", role: .destructive) { operation = "delete" } }
                        else { Button("退出群聊", role: .destructive) { operation = "leave" } }
                    } label: { Image(systemName: "ellipsis") }.disabled(busy)
                }
            }
    }
    var body: some View {
        roomContent
            .task {
                active = true
                if !restored { restored = true; ownerID = session.user?.id; if let ownerID { draft = ((try? session.store?.read(RoomDraft.self, account: ownerID, key: key)) ?? nil) ?? RoomDraft() } }
                session.stream.showRoom(roomID); await load()
            }
            .task(id: session.streamRevision) { if active && scenePhase == .active { await load() } }
            .task(id: session.connectionRevision) { if active && scenePhase == .active { await load() } }
            .onChange(of: draft.text) { _, _ in persist() }
            .onChange(of: scenePhase) { _, value in if value == .active && active { Task { await load() } } }
            .onDisappear { active = false; uploadTask?.cancel(); persist(); session.stream.showRoom(nil); preview = nil }
             .sheet(isPresented: $choosingFile) { DrivePicker { file in draft.file = file; persist() } }
            .sheet(isPresented: $choosingEmoji) { ReactionPicker { TextInsertion.insert($0, into: &draft.text, selection: &textSelection) } }
            .sheet(isPresented: $showingInfo) { NavigationStack { List { Text(room?["name"].string ?? "群聊").font(.headline); Text(room?["description"].string ?? "暂无群聊简介") }.puboList().navigationTitle("群聊信息").toolbar { Button("关闭") { showingInfo = false } } } }
            .photosPicker(isPresented: $choosingPhoto, selection: $selectedPhoto, matching: .any(of: [.images, .videos]))
            .onChange(of: selectedPhoto) { _, item in uploadTask = Task { await uploadPhoto(item) } }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item]) { result in uploadTask = Task { await uploadFile(result) } }
            .sheet(item: $preview) { file in PublicAttachmentPreview(file: file) }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { RoomEditor(room: room) }
            .sheet(item: $reactionTarget) { target in ReactionPicker { reaction in Task { await react(target, reaction) } } }
            .confirmationDialog("此操作会改变群聊及其成员的访问权限。是否继续？", isPresented: Binding(get: { operation != nil }, set: { if !$0 { operation = nil } })) { if let operation { Button(operation == "delete" ? "确认删除群聊" : "确认", role: .destructive) { Task { await perform(operation) } } } }
            .confirmationDialog("删除此群聊消息？", isPresented: Binding(get: { deletingMessage != nil }, set: { if !$0 { deletingMessage = nil } })) { if let message = deletingMessage { Button("删除消息", role: .destructive) { Task { await deleteMessage(message) } } } }
    }
    private func messageRow(_ message: Record) -> some View {
        let user = Record(message["fromUser"])
        let mine = message["fromUserId"].string == session.user?.id
        return HStack(alignment: .top, spacing: 8) {
            if mine { Spacer(minLength: 40) } else { Avatar(user: user, size: 42) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                if !mine { Text(user.displayName).font(.caption).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 7) {
                    if !message["recalledAt"].isNull { Text("消息已撤回") }
                    else {
                        if !message.text.isEmpty { NoteText(text: message.text, expands: false) }
                        if !message["file"].isNull { PublicMedia(file: Record(message["file"]), noteID: "", sourceURL: Endpoint.origin.appendingPathComponent("chat/room/" + roomID)).frame(maxWidth: 240) }
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10).background(mine ? PUBOTheme.ownBubble : PUBOTheme.panel, in: PUBOChatBubble(own: mine))
                    .accessibilityIdentifier("room.bubble." + message.id)
                    .contextMenu {
                        if message["recalledAt"].isNull {
                            Button("复制文字") { UIPasteboard.general.string = message.text }
                            if mine { Button("删除消息", role: .destructive) { deletingMessage = message } }
                            else { Button("添加反应") { reactionTarget = message } }
                        }
                    }
                if !message["reactions"].array.isEmpty && message["recalledAt"].isNull { ChatReactionStrip(reactions: message["reactions"].array, ownUserID: session.user?.id ?? "", enabled: !mine && !busy) { value in Task { await react(message, value) } } }
                if let date = puboDate(message["createdAt"].string) { Text(date, style: .time).font(.caption2).foregroundStyle(.secondary) }
            }
            if !mine { Spacer(minLength: 28) }
        }
    }
    @discardableResult private func persist() -> Bool {
        guard let ownerID, ownerID == session.user?.id else { return false }
        if session.testMode { return true }
        guard let store = session.store else { error = "无法保存待发状态，请稍后重试。"; return false }
        do { try store.save(draft, account: ownerID, key: key); return true } catch { self.error = "群聊草稿保存失败。"; return false }
    }
    private func load(older: Bool = false) async {
        guard active, scenePhase == .active, !loading else { return }; loading = true; defer { loading = false }
        do {
            let fresh = Record(try await session.call("chat/rooms/show", ["roomId": .string(roomID)])); try Task.checkCancellation(); guard active else { return }; guard !fresh.id.isEmpty else { throw APIError.invalidResponse }; room = fresh
            if fresh["invitationExists"].bool { messages = []; return }
            var fields: [String: JSONValue] = ["roomId": .string(roomID), "limit": .number(30)]
            if older, let id = messages.first?.id { fields["untilId"] = .string(id) }
            // This existing endpoint marks a room read, so it is used only while this room is visible.
            let value = try await session.call("chat/messages/room-timeline", fields); try Task.checkCancellation(); guard active, case .array = value else { return }
            let page = Record.list(value).sorted { $0.id < $1.id }
            if older { messages = Records.merge(messages, page, newestFirst: false, limit: 2000) }
            else {
                let floor = page.first?.id
                let retained = floor.map { boundary in messages.filter { $0.id < boundary } } ?? []
                messages = Records.merge(retained, page, newestFirst: false, limit: 2000)
                for id in session.changedChatIDs where messages.contains(where: { $0.id == id }) {
                    do { let value = Record(try await session.call("chat/messages/show", ["messageId": .string(id)])); if !value.id.isEmpty { messages = Records.merge(messages, [value], newestFirst: false, limit: 2000) } }
                    catch { if ["NO_SUCH_MESSAGE", "ACCESS_DENIED"].contains((error as? APIError)?.code ?? "") { messages.removeAll { $0.id == id } } }
                }
            }
            hasMore = page.count == 30; error = nil; await session.refreshUnread()
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; if (error as? APIError)?.code == "NO_SUCH_ROOM" { messages = []; room = nil; preview = nil } } }
    }
    private func send() async {
        if let sendProblem { error = sendProblem; return }; guard canSend else { return }
        busy = true; defer { busy = false }; draft.pending = true; guard persist() else { draft.pending = false; return }
        do {
            var fields: [String: JSONValue] = ["toRoomId": .string(roomID)]
            if !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields["text"] = .string(draft.text) }; if let file = draft.file { fields["fileId"] = .string(file.id) }
            let result = Record(try await session.call("chat/messages/create-to-room", fields, mutation: true))
            guard !result.id.isEmpty else { throw APIError.uncertain }
            draft = RoomDraft(); persist(); error = nil; await load(); scrollRequest += 1
        } catch { if let apiError = error as? APIError, apiError.code != "OUTCOME_UNKNOWN" { draft.pending = false; persist() }; self.error = error.localizedDescription }
    }
    private func perform(_ action: String) async {
        guard !busy else { return }; busy = true; defer { busy = false; operation = nil }
        do {
            _ = try await session.call("chat/rooms/" + action, ["roomId": .string(roomID)], mutation: true)
            if action == "join" { await load() } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
    private func mute() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { _ = try await session.call("chat/rooms/mute", ["roomId": .string(roomID), "mute": .bool(!(room?["isMuted"].bool ?? false))], mutation: true); await load() } catch { self.error = error.localizedDescription }
    }
    private func deleteMessage(_ message: Record) async {
        guard !busy else { return }; busy = true; defer { busy = false; deletingMessage = nil }
        do { _ = try await session.call("chat/messages/delete", ["messageId": .string(message.id)], mutation: true); messages.removeAll { $0.id == message.id }; await load() } catch { self.error = error.localizedDescription }
    }
    private func react(_ message: Record, _ reaction: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let fresh = Record(try await session.call("chat/messages/show", ["messageId": .string(message.id)]))
            guard !fresh.id.isEmpty, fresh["recalledAt"].isNull, fresh["fromUserId"].string != session.user?.id else { return }
            let key = SocialContent.chatReactionKey(reaction)
            let mine = fresh["reactions"].array.contains { $0["user"]["id"].string == session.user?.id && SocialContent.chatReactionKey($0["reaction"].string ?? "") == key }
            _ = try await session.call(mine ? "chat/messages/unreact" : "chat/messages/react", ["messageId": .string(message.id), "reaction": .string(reaction)], mutation: true); await load()
        } catch { let issue = error.localizedDescription; await load(); self.error = issue }
    }
    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard !busy, !draft.pending, let item else { return }; busy = true; defer { busy = false; selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first ?? .data
            try await attach(data, name: "PUBO-群聊.\(type.preferredFilenameExtension ?? "bin")", type: type)
        } catch { if active && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func uploadFile(_ result: Result<URL, Error>) async {
        guard !busy, !draft.pending else { return }; busy = true; defer { busy = false }
        do {
            let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "文件超过 50 MiB。") }
            try await attach(Data(contentsOf: url), name: url.lastPathComponent, type: UTType(filenameExtension: url.pathExtension) ?? .data)
        } catch { if active && !Task.isCancelled && (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription } }
    }
    private func attach(_ data: Data, name: String, type: UTType) async throws {
        guard active, ownerID == session.user?.id, !Task.isCancelled else { return }
        guard data.count <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "文件超过 50 MiB。") }
        let generation = session.generation
        let file = try await session.upload(data: data, name: name, mime: type.preferredMIMEType ?? "application/octet-stream")
        guard active, generation == session.generation, !Task.isCancelled else { return }
        draft.file = file; persist(); error = nil
    }
}
