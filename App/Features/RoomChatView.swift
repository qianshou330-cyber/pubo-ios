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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var messageFont = 12.6
    let roomID: String
    var initialMessage: Record? = nil
    @State private var room: Record?
    @State private var messages: [Record] = []
    @State private var draft = RoomDraft()
    @State private var ownerID: String?
    @State private var error: String?
    @State private var busy = false
    @State private var loading = false
    @State private var hasMore = false
    @State private var initialLoadCompleted = false
    @State private var loadError: String?
    @State private var retryOlder = false
    @State private var active = false
    @State private var restored = false
    @State private var choosingFile = false
    @State private var importingFile = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var choosingEmoji = false
    @State private var section = "messages"
    @State private var reporting: Record?
    @State private var visibleMessageID: String?
    @State private var scrollAnchor: UnitPoint = .bottom
    @State private var highlightedID: String?
    @State private var contextMode = false
    @State private var scrollTarget: String?
    @State private var animatedIDs = Set<String>()
    @State private var loadEpoch = UUID()
    @State private var needsReconcile = false
    @State private var textSelection = NSRange(location: 0, length: 0)
    @State private var nearBottom = true
    @State private var unreadBelow = false
    @State private var scrollRequest = 0
    @State private var uploadTask: Task<Void, Never>?
    private var chatProblem: String? { ChatEligibility.problem(account: session.user) }
    private var sendProblem: String? { SendFeedback.limitError(draft.text, limit: 2000) }
    @State private var preview: Record?
    @State private var editing = false
    @State private var operation: String?
    @State private var reactionTarget: Record?
    @State private var deletingMessage: RoomMessageDeletionIntent?
    @State private var deletionScreenID = UUID()
    @State private var deletionRequestID: UUID?
    private var own: Bool { room?["ownerId"].string == session.user?.id }
    private var invited: Bool { room?["invitationExists"].bool ?? false }
    private var key: String { "room-draft-" + roomID }
    private var canSend: Bool { chatProblem == nil && !draft.pending && !busy && sendProblem == nil && room != nil && !invited && (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.file != nil) }

    private var timeline: some View {
        GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let loadError, !messages.isEmpty {
                            VStack(spacing: 4) {
                                Text(loadError).font(.caption).foregroundStyle(.red).accessibilityIdentifier("room.loadError")
                                Button(retryOlder ? "重试加载更早消息" : "重试同步消息") { Task { await load(older: retryOlder, reconcile: !retryOlder) } }
                                    .frame(minHeight: 44).disabled(loading).accessibilityIdentifier("room.retry")
                            }.padding(.top, 16)
                        }
                        if hasMore { Button("更早的群聊消息") { Task { await load(older: true) } }.disabled(loading).padding(.top, loadError != nil && !messages.isEmpty ? 0 : 16) }
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            VStack(spacing: 12) {
                                if let pair = ChatDays.pair(previous: index > 0 ? messages[index - 1] : nil, current: message) { ChatDateSeparator(pair: pair, style: .room) }
                                messageRow(message)
                            }.padding(.top, index == 0 && !hasMore && !(loadError != nil && !messages.isEmpty) ? 16 : 0).id(message.id).modifier(ChatMessageEntrance(animate: animatedIDs.contains(message.id), distance: 80))
                                .background(highlightedID == message.id ? PUBOTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .onDisappear { animatedIDs.remove(message.id) }
                        }
                        Color.clear.frame(height: 1).id("bottom").background(GeometryReader { geo in Color.clear.preference(key: ChatBottomPreference.self, value: geo.frame(in: .named("roomScroll")).maxY) })
                    }.scrollTargetLayout().padding(.bottom, 16)
                }.contentMargins(.horizontal, 16, for: .scrollContent)
                    .accessibilityIdentifier("room.timeline")
                    .scrollPosition(id: $visibleMessageID, anchor: scrollAnchor).coordinateSpace(name: "roomScroll").scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(ChatBottomPreference.self) { bottom in nearBottom = bottom <= viewport.size.height + 80; if nearBottom { unreadBelow = false } }
                    .onChange(of: messages.last?.id) { old, _ in if !contextMode && (old == nil || nearBottom) { positionTimeline("bottom") } else if !contextMode { unreadBelow = true } }
                    .onChange(of: scrollTarget) { _, id in if let id { positionTimeline(id) } }
                    .onChange(of: scrollRequest) { _, _ in positionTimeline("bottom"); unreadBelow = false }
        }
    }
    private func positionTimeline(_ id: String) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { scrollAnchor = id == "bottom" ? .bottom : .top; visibleMessageID = id }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if unreadBelow || contextMode { Button(unreadBelow ? "有新消息 · 回到最新" : "回到最新消息") { Task { await returnToLatest() } }.frame(minHeight: 44) }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("room.error") }
            if let chatProblem { Text(chatProblem).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("room.availability") }
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
            CursorTextEditor(text: $draft.text, selection: $textSelection, enabled: !busy && !draft.pending && chatProblem == nil, identifier: "room.input", placeholder: "在此输入信息")
                .overlay(alignment: .topLeading) { if draft.text.isEmpty { Text("在此输入信息").font(.subheadline).foregroundStyle(PUBOTheme.secondary.opacity(0.65)).padding(.top, 8).allowsHitTesting(false) } }
            HStack(spacing: 4) {
                Menu {
                    Button("从网盘选择") { choosingFile = true }
                    Button("选择本地文件") { importingFile = true }
                    Button("选择图片或视频") { choosingPhoto = true }
                } label: { Image(systemName: "paperclip").frame(width: 44, height: 44) }.disabled(busy || draft.pending).accessibilityLabel("添加群聊附件").accessibilityIdentifier("room.attachments")
                Button { choosingEmoji = true } label: { Image(systemName: "face.smiling").frame(width: 44, height: 44) }.disabled(busy || draft.pending).accessibilityLabel("插入群聊表情").accessibilityIdentifier("room.emoji")
                Spacer(minLength: 0)
                Button { Task { await send() } } label: { Group { if busy { ProgressView() } else { Image(systemName: "paperplane").font(.title3) } }.frame(width: 44, height: 44) }.disabled(!canSend).accessibilityLabel("发送").accessibilityIdentifier("room.send")
            }.buttonStyle(.borderless).disabled(chatProblem != nil)
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            .background(PUBOTheme.panel.ignoresSafeArea(.container, edges: .bottom))
            .overlay(alignment: .top) { PUBOTheme.divider.frame(height: 0.5) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("room.composer")
    }
    private var roomContent: some View {
        Group {
            if invited {
                VStack(spacing: 20) { Text("你受邀加入此群聊"); Text(room?["name"].string ?? "").font(.headline); Button("接受邀请并加入") { Task { await perform("join") } }; Button("忽略邀请") { operation = "invitations/ignore" } }.padding()
            } else {
                VStack(spacing: 0) {
                    ChatTabs(selection: $section, items: [ChatTab(id: "messages", title: "消息", icon: "bubble.left.and.bubble.right"), ChatTab(id: "members", title: "成员", icon: "person.2"), ChatTab(id: "search", title: "搜索", icon: "magnifyingglass"), ChatTab(id: "about", title: "关于", icon: "info.circle")], prefix: "room.tab.")
                    if section == "messages" {
                        ChatConnectionStatus(phase: session.streamConnection, synchronizing: initialLoadCompleted && loading && !retryOlder, prefix: "room") {
                            session.stream.reconnectNow(); Task { await load(reconcile: true) }
                        }
                        ZStack {
                            timeline
                            ChatTimelineStatus(loaded: initialLoadCompleted, loading: loading, isEmpty: messages.isEmpty, error: loadError, prefix: "room") { Task { await load() } }
                        }.clipped()
                    }
                    else if section == "members" { RoomMembersView(roomID: roomID, canInvite: own, embedded: true, owner: room.map { Record($0["owner"]) }) }
                    else if section == "search" { List { ChatSearchView(roomID: roomID, embedded: true, selectMessage: { message in section = "messages"; Task { await openContext(message) } }) }.puboList() }
                    else { List {
                        Section("名称") { Text(room?["name"].string ?? "群聊") }
                        Section("描述") { Text(room?["description"].string ?? "暂无群聊简介") }
                        if !own { Toggle("消息免打扰", isOn: Binding(get: { room?["isMuted"].bool ?? false }, set: { _ in Task { await mute() } })).disabled(busy) }
                    }.puboList().accessibilityIdentifier("room.about") }
                }.safeAreaInset(edge: .bottom, spacing: 0) {
                    if section == "messages" { composer.fixedSize(horizontal: false, vertical: true) }
                }
            }
        }.navigationTitle(room?["name"].string ?? "群聊").puboScreen().toolbar(.hidden, for: .tabBar)
            .modifier(ConversationTabSuppression())
            .toolbar {
                if room != nil && !invited {
                    Menu {
                        Toggle("显示发送者昵称", isOn: Binding(get: { session.chatShowSenderName }, set: { session.setChatShowSenderName($0) }))
                        Button("群聊成员") { section = "members" }
                        Button("搜索本群") { section = "search" }
                        if !own { Button(room?["isMuted"].bool == true ? "恢复提醒" : "免打扰") { Task { await mute() } } }
                        if own { Button("修改群聊") { editing = true }; Button("删除群聊", role: .destructive) { operation = "delete" } }
                        else { Button("退出群聊", role: .destructive) { operation = "leave" } }
                    } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.disabled(busy)
                }
            }
    }
    var body: some View {
        roomContent
            .task {
                active = true
                if !restored { restored = true; ownerID = session.user?.id; if let ownerID { draft = ((try? session.store?.read(RoomDraft.self, account: ownerID, key: key)) ?? nil) ?? RoomDraft() } }
                session.stream.showRoom(roomID); await load(); if let initialMessage { await openContext(initialMessage) }
            }
            .task(id: session.generation) { await session.restoreChatPreferences() }
            .onChange(of: session.streamRevision) { _, _ in if active && scenePhase == .active { Task { await load() } } }
            .onChange(of: session.connectionRevision) { _, _ in if active && scenePhase == .active { Task { await load(reconcile: true) } } }
            .onReceive(session.chatEvents) { receive($0) }
            .onChange(of: session.generation) { _, _ in invalidateMessageDeletion() }
            .onChange(of: section) { _, value in invalidateMessageDeletion(); if value == "messages" { Task { await load(reconcile: true) } } }
            .onChange(of: draft.text) { _, _ in persist() }
            .onChange(of: scenePhase) { _, value in if value == .active && active { Task { await load(reconcile: true) } } }
            .onDisappear { invalidateMessageDeletion(); active = false; loadEpoch = UUID(); uploadTask?.cancel(); persist(); session.stream.showRoom(nil); preview = nil }
             .sheet(isPresented: $choosingFile) { DrivePicker { file in draft.file = file; persist() } }
            .sheet(isPresented: $choosingEmoji) { ReactionPicker { TextInsertion.insert($0, into: &draft.text, selection: &textSelection) } }
            .sheet(item: $reporting) { message in ReportView(userID: message["fromUserId"].string ?? "", context: Endpoint.origin.appendingPathComponent("chat/messages/" + message.id).absoluteString + "\n-----\n") }
            .photosPicker(isPresented: $choosingPhoto, selection: $selectedPhoto, matching: .any(of: [.images, .videos]))
            .onChange(of: selectedPhoto) { _, item in uploadTask = Task { await uploadPhoto(item) } }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item]) { result in uploadTask = Task { await uploadFile(result) } }
            .sheet(item: $preview) { file in PublicAttachmentPreview(file: file) }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { RoomEditor(room: room) }
            .sheet(item: $reactionTarget) { target in ReactionPicker { reaction in Task { await react(target, reaction) } } }
            .confirmationDialog("此操作会改变群聊及其成员的访问权限。是否继续？", isPresented: Binding(get: { operation != nil }, set: { if !$0 { operation = nil } })) { if let operation { Button(operation == "delete" ? "确认删除群聊" : "确认", role: .destructive) { Task { await perform(operation) } } } }
            // A confirmationDialog may adapt to a popover with no visible Cancel action.
            // An alert keeps both choices explicit for touch and VoiceOver on every size.
            .alert("删除此群聊消息？", isPresented: Binding(get: { deletingMessage != nil }, set: { if !$0 { deletingMessage = nil } })) {
                if let intent = deletingMessage {
                    Button("删除消息", role: .destructive) { confirmMessageDeletion(intent) }
                }
                Button("取消", role: .cancel) { deletingMessage = nil }
            }
    }
    private func messageRow(_ message: Record) -> some View {
        let user = Record(message["fromUser"])
        let mine = message["fromUserId"].string == session.user?.id
        return HStack(alignment: .top, spacing: 8) {
            if mine { Spacer(minLength: 40) } else { NavigationLink { ProfileView(userID: user.id) } label: { Avatar(user: user, size: 42).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(user.displayName + "的主页").accessibilityIdentifier("room.avatar." + message.id) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                if !mine && session.chatShowSenderName {
                    Text(user.displayName).font(.caption).foregroundStyle(PUBOTheme.secondary).lineLimit(2)
                        .accessibilityIdentifier("room.sender." + message.id)
                }
                VStack(alignment: .leading, spacing: 7) {
                    if !message["recalledAt"].isNull { Text("消息已撤回") }
                    else {
                        if !message.text.isEmpty { ChatMessageContent(text: message.text, active: section == "messages" && preview == nil, identifier: "room.text." + message.id, remoteEmojis: message["emojis"], menuActions: messageActions(message, mine: mine)).font(.system(size: messageFont)) }
                        if !message["file"].isNull { PublicMedia(file: Record(message["file"]), noteID: "", sourceURL: Endpoint.origin.appendingPathComponent("chat/room/" + roomID)).frame(maxWidth: 240) }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 8).background(mine ? PUBOTheme.ownBubble : PUBOTheme.panel, in: PUBOChatBubble(own: mine))
                    .accessibilityIdentifier("room.bubble." + message.id)
                    .contextMenu { messageMenu(message, mine: mine) }
                if message["recalledAt"].isNull && !ChatContentPolicy.previewLinks(message.text).isEmpty {
                    ChatMessageLinkPreviews(text: message.text, active: section == "messages" && preview == nil, identifier: "room.links." + message.id)
                }
                HStack(spacing: 6) {
                    if !mine { Menu { messageMenu(message, mine: mine) } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("群消息菜单").accessibilityIdentifier("room.menu." + message.id) }
                    if let date = puboDate(message["createdAt"].string) { ChatRelativeTime(date: date).font(.caption2).foregroundStyle(.secondary) }
                    if mine { Menu { messageMenu(message, mine: mine) } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("群消息菜单").accessibilityIdentifier("room.menu." + message.id) }
                }
                if !message["reactions"].array.isEmpty && message["recalledAt"].isNull { ChatReactionStrip(reactions: message["reactions"].array, ownUserID: session.user?.id ?? "", enabled: !mine && !busy) { value, desired in Task { await react(message, value, requested: desired) } } }
            }
            if !mine { Spacer(minLength: 28) }
        }
    }
    private func messageMenu(_ message: Record, mine: Bool) -> some View {
        ChatMenuButtons(actions: messageActions(message, mine: mine))
    }
    private func messageActions(_ message: Record, mine: Bool) -> [ChatMenuAction] {
        guard message["recalledAt"].isNull else { return [] }
        let epoch = session.generation
        let owner = session.user?.id
        func command(_ id: String, _ title: String, destructive: Bool = false, enabled: Bool = true, _ perform: @escaping () -> Void) -> ChatMenuAction {
            ChatMenuAction(id: id, title: title, destructive: destructive, enabled: enabled) {
                guard active, scenePhase == .active, section == "messages", preview == nil,
                      epoch == session.generation, owner == session.user?.id,
                      let current = messages.first(where: { $0.id == message.id }),
                      current["recalledAt"].isNull, current.raw == message.raw else { return }
                perform()
            }
        }
        var actions: [ChatMenuAction] = []
        if !message.text.isEmpty { actions.append(command("room.copy." + message.id, "复制文字") { UIPasteboard.general.string = message.text }) }
        if mine { actions.append(command("room.delete." + message.id, "删除消息", destructive: true) { requestMessageDeletion(message) }) }
        else {
            actions.append(command("room.react." + message.id, "添加反应") { reactionTarget = message })
            actions.append(command("room.report." + message.id, "举报", enabled: message["fromUserId"].string != nil) { reporting = message })
        }
        return actions
    }
    private func receive(_ event: ChatStreamEvent) {
        guard active, event.room, event.targetID == roomID, scenePhase == .active else { return }
        if event.kind == "message" {
            let row = Record(event.body)
            guard !row.id.isEmpty, row["toRoomId"].string == roomID else { return }
            if contextMode { unreadBelow = true; return }
            if !messages.contains(where: { $0.id == row.id }) && section == "messages" { animatedIDs.insert(row.id) }
            messages = Records.merge(messages, [row], newestFirst: false, limit: 2000)
        } else if event.kind == "deleted", let id = event.messageID {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { messages.removeAll { $0.id == id } }
            if preview != nil { preview = nil }
        } else if ["react", "unreact"].contains(event.kind), let id = event.messageID, let index = messages.firstIndex(where: { $0.id == id }), let uid = event.body["user"]["id"].string, let emoji = event.body["reaction"].string {
            var value = messages[index].raw.object
            var reactions = value["reactions"]?.array ?? []
            reactions.removeAll { $0["user"]["id"].string == uid && SocialContent.chatReactionKey($0["reaction"].string ?? "") == SocialContent.chatReactionKey(emoji) }
            if event.kind == "react" { reactions.append(.object(["user": event.body["user"], "reaction": .string(emoji)])) }
            value["reactions"] = .array(reactions); messages[index] = Record(.object(value))
        }
    }
    private func around(_ target: Record) async throws -> [Record] {
        guard active, section == "messages", scenePhase == .active, let date = ChatDays.date(target["createdAt"].string) else { throw APIError.invalidResponse }
        let value = try await session.call("chat/messages/room-timeline", ["roomId": .string(roomID), "limit": .number(100), "sinceDate": .number(floor(date.timeIntervalSince1970 * 1000) - 1)])
        try Task.checkCancellation(); guard case .array = value else { throw APIError.invalidResponse }
        return Record.list(value).filter { $0["toRoomId"].string == roomID }
    }
    private func openContext(_ target: Record) async {
        guard target["toRoomId"].string == roomID else { return }
        loadEpoch = UUID(); let epoch = loadEpoch
        do {
            let after = try await around(target)
            guard after.contains(where: { $0.id == target.id }) else { throw APIError(code: "NO_SUCH_MESSAGE", message: "此消息已不可用，未跳转到其他消息。") }
            let before = Record.list(try await session.call("chat/messages/room-timeline", ["roomId": .string(roomID), "limit": .number(30), "untilId": .string(target.id)]))
            guard active, epoch == loadEpoch, !Task.isCancelled else { return }
            contextMode = true; messages = Records.merge(before, after, newestFirst: false, limit: 2000); hasMore = before.count == 30
            highlightedID = target.id; error = nil; scrollTarget = nil
            await Task.yield(); guard active, epoch == loadEpoch else { return }; scrollTarget = target.id
        } catch { if active && epoch == loadEpoch { self.error = error.localizedDescription } }
    }
    private func returnToLatest() async {
        guard active, section == "messages" else { return }
        loadEpoch = UUID(); let epoch = loadEpoch
        do {
            let value = try await session.call("chat/messages/room-timeline", ["roomId": .string(roomID), "limit": .number(30)])
            guard active, epoch == loadEpoch, section == "messages", !Task.isCancelled, case .array = value else { return }
            let page = Record.list(value).filter { $0["toRoomId"].string == roomID }
            // A historical context and the newest page may have an unloaded gap.
            // Restart pagination at the newest page instead of joining those windows.
            messages = Records.merge([], page, newestFirst: false, limit: 2000)
            hasMore = page.count == 30; contextMode = false; highlightedID = nil
            animatedIDs.removeAll(); unreadBelow = false; error = nil
            await Task.yield(); guard active, epoch == loadEpoch else { return }; scrollRequest += 1
        } catch { if active && epoch == loadEpoch { self.error = error.localizedDescription } }
    }
    @discardableResult private func persist() -> Bool {
        guard let ownerID, ownerID == session.user?.id else { return false }
        if session.testMode && session.store == nil { return true }
        guard let store = session.store else { error = "无法保存待发状态，请稍后重试。"; return false }
        do { try store.save(draft, account: ownerID, key: key); return true } catch { self.error = "群聊草稿保存失败。"; return false }
    }
    private func load(older: Bool = false, reconcile: Bool = false) async {
        if reconcile { needsReconcile = true }
        guard active, scenePhase == .active, !loading else { return }
        loading = true
        let reconcile = needsReconcile && !older; if reconcile { needsReconcile = false }
        defer { loading = false; if active && needsReconcile && section == "messages" { Task { await load() } } }
        let epoch = loadEpoch
        retryOlder = older; loadError = nil
        do {
            let fresh = Record(try await session.call("chat/rooms/show", ["roomId": .string(roomID)])); try Task.checkCancellation()
            guard active, epoch == loadEpoch else { return }; guard !fresh.id.isEmpty else { throw APIError.invalidResponse }; room = fresh
            if fresh["invitationExists"].bool { messages = []; initialLoadCompleted = true; return }
            // This endpoint marks read; search/members/about never call it.
            guard section == "messages", !contextMode || older || reconcile else { return }
            var fields: [String: JSONValue] = ["roomId": .string(roomID), "limit": .number(reconcile ? 100 : 30)]
            if older, let id = messages.first?.id { fields["untilId"] = .string(id) }
            if contextMode && reconcile, let last = messages.last, let date = ChatDays.date(last["createdAt"].string) { fields["untilDate"] = .number(floor(date.timeIntervalSince1970 * 1000) + 1) }
            let oldFloor = messages.first?.id
            var page: [Record] = []
            var lastCount = 0
            repeat {
                let value = try await session.call("chat/messages/room-timeline", fields); try Task.checkCancellation()
                guard active, epoch == loadEpoch, section == "messages", case .array = value else { return }
                let batch = Record.list(value).filter { $0["toRoomId"].string == roomID }; lastCount = batch.count
                page = Records.merge(page, batch, newestFirst: false, limit: 2000)
                if !reconcile || lastCount < 100 || page.count >= 2000 || oldFloor == nil || (page.first?.id ?? "") <= oldFloor! { break }
                guard let cursor = page.first?.id, fields["untilId"]?.string != cursor else { break }; fields["untilId"] = .string(cursor)
            } while !Task.isCancelled
            if older { messages = Records.merge(messages, page, newestFirst: false, limit: 2000); hasMore = lastCount == 30 }
            else if reconcile { messages = page; hasMore = lastCount == 100 }
            else {
                let retained = page.first.map { boundary in messages.filter { $0.id < boundary.id } } ?? []
                let wasEmpty = messages.isEmpty; messages = Records.merge(retained, page, newestFirst: false, limit: 2000)
                if wasEmpty { hasMore = lastCount == 30 }
            }
            initialLoadCompleted = true; loadError = nil; await session.refreshUnread()
        } catch {
            if active && epoch == loadEpoch && !Task.isCancelled {
                self.loadError = error.localizedDescription
                if ["NO_SUCH_ROOM", "ACCESS_DENIED", "PERMISSION_DENIED"].contains((error as? APIError)?.code ?? "") { messages = []; room = nil; preview = nil }
            }
        }
    }
    private func send() async {
        if let chatProblem { error = chatProblem; return }
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
    private func invalidateMessageDeletion() {
        deletingMessage = nil; deletionScreenID = UUID()
        if deletionRequestID != nil { deletionRequestID = nil; busy = false }
    }
    private func deletionContextMatches(_ intent: RoomMessageDeletionIntent) -> Bool {
        ownerID == intent.ownerID && intent.matches(ownerID: session.user?.id, generation: session.generation,
            screenID: deletionScreenID, roomID: roomID, active: active && section == "messages")
    }
    private func requestMessageDeletion(_ message: Record) {
        guard !busy, active, section == "messages", let ownerID, ownerID == session.user?.id,
              let intent = RoomMessageDeletionIntent(ownerID: ownerID, generation: session.generation,
                  screenID: deletionScreenID, roomID: roomID, message: message),
              intent.permits(messages.first { $0.id == intent.messageID }) else { return }
        deletingMessage = intent
    }
    private func confirmMessageDeletion(_ intent: RoomMessageDeletionIntent) {
        guard deletingMessage == intent, !busy, deletionRequestID == nil,
              deletionContextMatches(intent), intent.permits(messages.first { $0.id == intent.messageID }) else { return }
        // Consume synchronously: a second tap cannot create a second request.
        deletingMessage = nil; let requestID = UUID(); deletionRequestID = requestID; busy = true
        Task { await deleteMessage(intent, requestID: requestID) }
    }
    private func deleteMessage(_ intent: RoomMessageDeletionIntent, requestID: UUID) async {
        defer {
            if deletionRequestID == requestID && deletionContextMatches(intent) {
                deletionRequestID = nil; busy = false
            }
        }
        // Task scheduling is an interruption point, so check again before transmission.
        guard deletionRequestID == requestID, deletionContextMatches(intent), !Task.isCancelled,
              intent.permits(messages.first { $0.id == intent.messageID }) else { return }
        do {
            _ = try await session.call("chat/messages/delete", ["messageId": .string(intent.messageID)], mutation: true)
            guard deletionRequestID == requestID, deletionContextMatches(intent), !Task.isCancelled else { return }
            messages.removeAll { $0.id == intent.messageID }; error = nil
            // No trailing reload: the stream will reconcile; an old task must not start
            // another account's load after its delete response.
        } catch {
            guard deletionRequestID == requestID, deletionContextMatches(intent), !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
    private func react(_ message: Record, _ reaction: String, requested: Bool = true) async {
        guard active, section == "messages", !busy, let viewer = session.user?.id else { return }; busy = true; defer { busy = false }
        let epoch = session.generation
        let key = SocialContent.chatReactionKey(reaction)
        func hasMine(_ row: Record) -> Bool { row["reactions"].array.contains { ($0["user"]["id"].string ?? $0["userId"].string) == viewer && SocialContent.chatReactionKey($0["reaction"].string ?? "") == key } }
        var desired: Bool?
        do {
            guard let fresh = try await around(message).first(where: { $0.id == message.id }), fresh["recalledAt"].isNull, fresh["fromUserId"].string != viewer else { throw APIError.invalidResponse }
            desired = requested
            if hasMine(fresh) == requested { messages = Records.merge(messages, [fresh], newestFirst: false, limit: 2000); error = nil; return }
            _ = try await session.call(desired == true ? "chat/messages/react" : "chat/messages/unreact", ["messageId": .string(message.id), "reaction": .string(reaction)], mutation: true)
            guard let check = try await around(message).first(where: { $0.id == message.id }), hasMine(check) == (desired ?? false) else { throw APIError.uncertain }
            guard active, epoch == session.generation else { return }
            messages = Records.merge(messages, [check], newestFirst: false, limit: 2000); error = nil
        } catch {
            let issue = error
            guard active, epoch == session.generation else { return }
            if let desired, let page = try? await around(message), let check = page.first(where: { $0.id == message.id }), hasMine(check) == desired, active, epoch == session.generation {
                messages = Records.merge(messages, [check], newestFirst: false, limit: 2000); self.error = nil
            } else if active, epoch == session.generation { self.error = issue.localizedDescription }
        }
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
