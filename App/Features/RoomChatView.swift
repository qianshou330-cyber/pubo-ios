import SwiftUI
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
    @State private var preview: Record?
    @State private var editing = false
    @State private var operation: String?
    @State private var reactionTarget: Record?
    @State private var deletingMessage: Record?
    private var own: Bool { room?["ownerId"].string == session.user?.id }
    private var invited: Bool { room?["invitationExists"].bool ?? false }
    private var key: String { "room-draft-" + roomID }
    private var canSend: Bool { !draft.pending && !busy && room != nil && !invited && (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.file != nil) }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if hasMore { Button("更早的群聊消息") { Task { await load(older: true) } }.disabled(loading) }
                    ForEach(messages) { message in messageRow(message).id(message.id) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding()
            }.onChange(of: messages.last?.id) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
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
            HStack {
                Button { choosingFile = true } label: { Image(systemName: "paperclip").frame(width: 44, height: 44) }.disabled(busy || draft.pending).accessibilityLabel("添加群聊网盘文件")
                TextField("群聊消息", text: $draft.text, axis: .vertical).lineLimit(1...4).disabled(busy || draft.pending)
                Button("发送") { Task { await send() } }.disabled(!canSend).frame(minHeight: 44)
            }
        }.padding().background(PUBOTheme.panel)
    }
    private var roomContent: some View {
        Group {
            if invited {
                VStack(spacing: 20) { Text("你受邀加入此群聊"); Text(room?["name"].string ?? "").font(.headline); Button("接受邀请并加入") { Task { await perform("join") } }; Button("忽略邀请") { operation = "invitations/ignore" } }.padding()
            } else { timeline.safeAreaInset(edge: .bottom) { composer } }
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
            .onDisappear { active = false; persist(); session.stream.showRoom(nil); preview = nil }
            .sheet(isPresented: $choosingFile) { DrivePicker { file in draft.file = file; persist() } }
            .sheet(item: $preview) { file in PublicAttachmentPreview(file: file) }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { RoomEditor(room: room) }
            .sheet(item: $reactionTarget) { target in ReactionPicker { reaction in Task { await react(target, reaction) } } }
            .confirmationDialog("此操作会改变群聊及其成员的访问权限。是否继续？", isPresented: Binding(get: { operation != nil }, set: { if !$0 { operation = nil } })) { if let operation { Button(operation == "delete" ? "确认删除群聊" : "确认", role: .destructive) { Task { await perform(operation) } } } }
            .confirmationDialog("删除此群聊消息？", isPresented: Binding(get: { deletingMessage != nil }, set: { if !$0 { deletingMessage = nil } })) { if let message = deletingMessage { Button("删除消息", role: .destructive) { Task { await deleteMessage(message) } } } }
    }
    private func messageRow(_ message: Record) -> some View {
        let user = Record(message["fromUser"])
        return HStack(alignment: .top) {
            Avatar(user: user)
            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName).font(.caption).foregroundStyle(.secondary)
                if !message["recalledAt"].isNull { Text("消息已撤回") }
                else {
                    if !message.text.isEmpty { NoteText(text: message.text, expands: false) }
                    if !message["file"].isNull { Button { preview = Record(message["file"]) } label: { Label(message["file"]["name"].string ?? "附件", systemImage: "paperclip") } }
                    if !message["reactions"].array.isEmpty { Text(message["reactions"].array.compactMap { $0["reaction"].string }.joined(separator: " ")) }
                }
                if let date = puboDate(message["createdAt"].string) { Text(date, style: .time).font(.caption2).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                Button("复制文字") { UIPasteboard.general.string = message.text }
                if message["fromUserId"].string == session.user?.id { Button("删除消息", role: .destructive) { deletingMessage = message } }
                else { Button("添加反应") { reactionTarget = message } }
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
            let fresh = Record(try await session.call("chat/rooms/show", ["roomId": .string(roomID)])); try Task.checkCancellation(); guard active else { return }; room = fresh
            if fresh["invitationExists"].bool { messages = []; return }
            var fields: [String: JSONValue] = ["roomId": .string(roomID), "limit": .number(30)]
            if older, let id = messages.first?.id { fields["untilId"] = .string(id) }
            // This existing endpoint marks a room read, so it is used only while this room is visible.
            let value = try await session.call("chat/messages/room-timeline", fields); try Task.checkCancellation(); guard active, case .array = value else { return }
            let page = Record.list(value).sorted { $0.id < $1.id }
            messages = older ? page.filter { p in !messages.contains { $0.id == p.id } } + messages : page
            hasMore = page.count == 30; error = nil; await session.refreshUnread()
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; if (error as? APIError)?.code == "NO_SUCH_ROOM" { messages = []; room = nil; preview = nil } } }
    }
    private func send() async {
        guard canSend, draft.text.unicodeScalars.count <= 2000 else { return }
        busy = true; defer { busy = false }; draft.pending = true; guard persist() else { draft.pending = false; return }
        do {
            var fields: [String: JSONValue] = ["toRoomId": .string(roomID)]
            if !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields["text"] = .string(draft.text) }; if let file = draft.file { fields["fileId"] = .string(file.id) }
            let result = Record(try await session.call("chat/messages/create-to-room", fields, mutation: true))
            guard !result.id.isEmpty else { throw APIError.uncertain }
            draft = RoomDraft(); persist(); error = nil; await load()
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
        do { _ = try await session.call("chat/messages/react", ["messageId": .string(message.id), "reaction": .string(reaction)], mutation: true); await load() } catch { self.error = error.localizedDescription }
    }
}
