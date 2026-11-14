import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PUBOCore
import SDWebImage

struct ChatView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var messageFont = 12.6
    let peer: Record
    var initialMessageID: String? = nil
    @State private var messages: [Record] = []
    @State private var pending: [PendingChat] = []
    @State private var text = ""
    @State private var textSelection = NSRange(location: 0, length: 0)
    @State private var nearBottom = true
    @State private var unreadBelow = false
    @State private var conversationSettings: JSONValue = .null
    @State private var settingBusy = false
    @State private var refreshedPeer: Record?
    private var chatProblem: String? { ChatEligibility.problem(account: session.user, peer: refreshedPeer ?? peer) }
    private var sendProblem: String? { SendFeedback.limitError(text, limit: 2000) }
    @State private var attachments: [Record] = []
    @State private var reply: Record?
    @State private var error: String?
    @State private var busy = false
    @State private var loading = false
    @State private var hasMore = false
    @State private var initialLoadCompleted = false
    @State private var loadError: String?
    @State private var retryOlder = false
    @State private var choosingPhoto = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var recorder = VoiceRecorder()
    @State private var restored = false
    @State private var ownerID: String?
    @State private var preview: PrivatePreviewItem?
    @State private var choosingEmoji = false
    @State private var stickerTask: Task<Void, Never>?
    @State private var stickerBusy = false
    @State private var stickerNotice: String?
    @State private var choosingDrive = false
    @State private var actionMessage: Record?
    @State private var reporting = false
    @State private var confirmBlock = false
    @State private var syncEpoch = UUID()
    @State private var needsFullState = false
    @State private var contextMode = false
    @State private var contextBusy = false
    @State private var hasNewer = false
    @State private var highlightedID: String?
    @State private var scrollTarget: String?
    @State private var searching = false
    @State private var active = false
    @State private var animatedIDs = Set<String>()
    @State private var visibleMessageID: String?
    @State private var scrollAnchor: UnitPoint = .bottom
    private var outboxKey: String { "chat-outbox-" + peer.id }
    private var draftKey: String { "chat-draft-" + peer.id }
    init(peer: Record, initialMessageID: String? = nil) { self.peer = peer; self.initialMessageID = initialMessageID; _contextMode = State(initialValue: initialMessageID != nil) }

    private var messageList: some View {
        LazyVStack(spacing: 18) {
            if let loadError, !messages.isEmpty {
                VStack(spacing: 4) {
                    Text(loadError).font(.caption).foregroundStyle(.red).accessibilityIdentifier("chat.loadError")
                    Button(retryOlder ? "重试加载更早消息" : "重试同步消息") { Task { await load(older: retryOlder) } }
                        .frame(minHeight: 44).disabled(loading).accessibilityIdentifier("chat.retry")
                }
            }
            if hasMore { Button("更早的消息") { Task { await load(older: true) } }.disabled(loading) }
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                VStack(spacing: 12) {
                    if let pair = ChatDays.pair(previous: index > 0 ? messages[index - 1] : nil, current: message) { ChatDateSeparator(pair: pair, style: .direct) }
                    bubble(message)
                }.id(message.id).modifier(ChatMessageEntrance(animate: animatedIDs.contains(message.id), distance: 12)).onDisappear { animatedIDs.remove(message.id) }
                    .background(highlightedID == message.id ? PUBOTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(pending) { item in pendingBubble(item) }
            Color.clear.frame(height: 1).id("bottom").background(GeometryReader { geo in Color.clear.preference(key: ChatBottomPreference.self, value: geo.frame(in: .named("privateScroll")).maxY) })
        }.scrollTargetLayout().padding(.vertical, 16)
    }
    private var messageScroll: some View {
        GeometryReader { viewport in
                ScrollView { messageList }.contentMargins(.horizontal, 16, for: .scrollContent).accessibilityIdentifier("chat.timeline").scrollPosition(id: $visibleMessageID, anchor: scrollAnchor).coordinateSpace(name: "privateScroll").scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(ChatBottomPreference.self) { bottom in nearBottom = bottom <= viewport.size.height + 80; if nearBottom { unreadBelow = false } }
                    .onChange(of: messages.last?.id) { old, _ in
                        if !contextMode && (old == nil || nearBottom) { positionTimeline("bottom") }
                        else if !contextMode { unreadBelow = true }
                    }
                    .onChange(of: pending.count) { old, count in if count > old { positionTimeline("bottom"); unreadBelow = false } }
                    .onChange(of: scrollTarget) { _, id in if let id { positionTimeline(id) } }
        }
    }
    private func positionTimeline(_ id: String) {
        // One binding owns programmatic and user scrolling, including estimated lazy rows.
        // Mixing ScrollViewReader with a top-anchored binding can stop before the last row.
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { scrollAnchor = id == "bottom" ? .bottom : .top; visibleMessageID = id }
    }
    private var chatLayout: some View {
        VStack(spacing: 0) {
            ChatTabs(selection: Binding(get: { searching ? "search" : "messages" }, set: { searching = $0 == "search" }), items: [ChatTab(id: "messages", title: "消息", icon: "bubble.left.and.bubble.right"), ChatTab(id: "search", title: "搜索", icon: "magnifyingglass")])
            ChatConnectionStatus(phase: session.streamConnection, synchronizing: initialLoadCompleted && loading && !retryOlder, prefix: "chat") {
                session.stream.reconnectNow(); Task { await load(reconcileAll: true) }
            }
            ZStack {
                messageScroll.opacity(searching ? 0 : 1).allowsHitTesting(!searching).accessibilityHidden(searching)
                if !searching {
                    ChatTimelineStatus(loaded: initialLoadCompleted, loading: loading, isEmpty: messages.isEmpty && pending.isEmpty, error: loadError, prefix: "chat") {
                        Task { await retryInitialLoad() }
                    }
                }
                if searching { ChatSearchView(peer: peer, select: { id in searching = false; Task { await openContext(id) } }).chatNavigationTitle(peer.displayName, embedded: false) }
            }.clipped()
        }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !searching { inputBar.fixedSize(horizontal: false, vertical: true) }
            }
            .modifier(ConversationTabSuppression())
            .puboScreen().navigationTitle(peer.displayName)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) { HStack(spacing: 8) { Avatar(user: peer, size: 32); Text(peer.displayName).font(.headline).lineLimit(1) } }
                ToolbarItem(placement: .topBarTrailing) { Menu {
                    if !conversationSettings.isNull {
                        Button(conversationSettings["pinnedAt"].isNull ? "置顶会话" : "取消置顶") { Task { await updateConversation("pinned", conversationSettings["pinnedAt"].isNull) } }.disabled(settingBusy)
                        Button(conversationSettings["isMuted"].bool ? "关闭免打扰" : "开启免打扰") { Task { await updateConversation("isMuted", !conversationSettings["isMuted"].bool) } }.disabled(settingBusy)
                    }
                    Button("搜索本会话") { searching = true }; Button("举报对方") { reporting = true }; Button("屏蔽对方", role: .destructive) { confirmBlock = true }; Link("在本站网页查看聊天", destination: Endpoint.origin.appendingPathComponent("chat/user/" + peer.id)) } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityLabel("聊天选项") }
            }
    }
    private var chatLifecycle: some View {
        chatLayout
            .task {
                active = true; session.stream.showChat(peer.id)
                if !restored { restored = true; ownerID = session.user?.id; restore() }
                await refreshPeer()
                if let initialMessageID { await openContext(initialMessageID) } else { await load() }; await loadConversation()
            }
            .task(id: session.generation) { await session.restoreChatPreferences() }
            .onChange(of: session.streamRevision) { _, _ in
                Task { guard active else { return }; try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { await load(); await loadConversation() } }
            }
            .onChange(of: session.connectionRevision) { _, _ in if active { Task { await load(reconcileAll: true) } } }
            .onReceive(session.chatEvents) { receive($0) }
            .onChange(of: text) { _, _ in saveDraft() }
            .onChange(of: photos) { _, items in Task { await uploadPhotos(items) } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stickerTask?.cancel(); recorder.cancel(); saveDraft() } else { Task { await load(reconcileAll: true) } } }
            .onChange(of: session.generation) { _, _ in stickerTask?.cancel(); stickerNotice = nil }
            .onDisappear { active = false; stickerTask?.cancel(); syncEpoch = UUID(); recorder.cancel(); saveDraft(); session.stream.showChat(nil) }
    }
    var body: some View {
        chatLifecycle

            .photosPicker(isPresented: $choosingPhoto, selection: $photos, maxSelectionCount: max(1, 10 - attachments.count), matching: .any(of: [.images, .videos]))
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in Task { await importFile(result) } }
            .sheet(isPresented: $choosingEmoji) { ChatEmojiPicker(chooseEmoji: { TextInsertion.insert($0, into: &text, selection: &textSelection) }, chooseGIF: { data in let epoch = session.generation; Task { guard epoch == session.generation else { return }; await attachSticker(data) } }) }
            .sheet(item: $preview) { item in PrivateAttachmentView(attachment: item.attachment) }
            .sheet(item: $actionMessage) { message in ChatMessageActions(message: message, peerID: peer.id, ownerID: session.user?.id ?? "") { updated in syncEpoch = UUID(); messages = ChatRecords.merge(messages, [updated]); updateDraft(targets: [updated], missing: []) } }
            .sheet(isPresented: $choosingDrive) { DrivePicker { file in Task { await importDrive(file) } } }
            .sheet(isPresented: $reporting) { ReportView(userID: peer.id, context: "私信会话：" + Endpoint.origin.appendingPathComponent("chat/user/" + peer.id).absoluteString) }
            .confirmationDialog("屏蔽对方后，将不能继续聊天。", isPresented: $confirmBlock) { Button("屏蔽对方", role: .destructive) { Task { do { _ = try await session.call("blocking/create", ["userId": .string(peer.id)], mutation: true); error = "已屏蔽对方" } catch { self.error = error.localizedDescription } } } }
    }
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let chatProblem { Text(chatProblem).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("chat.availability") }
            if contextMode { Text("正在查看历史消息，预取不会标记已读").font(.caption).foregroundStyle(.secondary) }
            if contextMode || hasNewer || unreadBelow { Button(unreadBelow ? "有新消息 · 回到最新" : "回到最新消息") { Task { await returnToLatest() } }.frame(minHeight: 44).disabled(contextBusy).accessibilityIdentifier("chat.latest") }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("chat.error") }
            if stickerBusy { ProgressView("正在收藏表情包…").font(.caption) }
            if let stickerNotice { Text(stickerNotice).font(.caption).foregroundStyle(PUBOTheme.secondary).accessibilityIdentifier("chat.sticker.notice") }
            if let reply { HStack { Text("回复：" + ChatReferences.label(ChatReferences.summary(reply))).lineLimit(2); Spacer(); Button("取消回复") { self.reply = nil; saveDraft() } }.font(.caption).padding(8).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8)) }
            if !attachments.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(attachments) { file in
                    HStack { Text(file["name"].string ?? "附件").lineLimit(1); Button { attachments.removeAll { $0.id == file.id }; stickerNotice = nil; saveDraft() } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("移除附件") }.font(.caption).padding(8).background(PUBOTheme.button, in: Capsule())
                } } }
            }
            CursorTextEditor(text: $text, selection: $textSelection, enabled: !busy && chatProblem == nil, identifier: "chat.input", placeholder: "在此输入信息")
                .overlay(alignment: .topLeading) { if text.isEmpty { Text("在此输入信息").font(.subheadline).foregroundStyle(PUBOTheme.secondary.opacity(0.65)).padding(.top, 8).allowsHitTesting(false) } }
            if let sendProblem { Text(sendProblem).font(.caption).foregroundStyle(.red).accessibilityIdentifier("chat.limit") }
            HStack(spacing: 6) {
                Menu {
                    Button("选择文件") { importing = true }
                    Button("添加图片或视频") { choosingPhoto = true }.disabled(attachments.count >= 10)
                    Button("从网盘导入") { choosingDrive = true }.disabled(attachments.count >= 10)
                    Button(recorder.recording ? "结束并添加语音" : "录制语音（最多60秒）") { Task { await voice() } }
                    if recorder.recording { Button("取消录音", role: .cancel) { recorder.cancel() } }
                } label: { Image(systemName: recorder.recording ? "mic.fill" : "paperclip").frame(width: 44, height: 44).foregroundStyle(recorder.recording ? .red : PUBOTheme.secondary) }.disabled(busy).accessibilityLabel("文件与语音").accessibilityIdentifier("chat.attachments")
                Button { Task { await voice() } } label: { Image(systemName: recorder.recording ? "stop.circle.fill" : "mic").frame(width: 44, height: 44).foregroundStyle(recorder.recording ? .red : PUBOTheme.secondary) }.disabled(busy || attachments.count >= 10).accessibilityLabel(recorder.recording ? "结束并添加语音" : "录制语音").accessibilityIdentifier("chat.voice")
                Button { choosingEmoji = true } label: { Image(systemName: "face.smiling").frame(width: 44, height: 44) }.accessibilityLabel("插入表情").accessibilityIdentifier("chat.emoji")
                Spacer(minLength: 0)
                Button { Task { await sendNew() } } label: {
                    Group { if busy { ProgressView() } else { Image(systemName: "paperplane").font(.title3) } }.frame(width: 44, height: 44).foregroundStyle(PUBOTheme.accent)
                }.disabled(busy || sendProblem != nil || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)).accessibilityLabel("发送消息").accessibilityIdentifier("chat.send")
            }.buttonStyle(.borderless).disabled(chatProblem != nil)
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            .background(PUBOTheme.panel.ignoresSafeArea(.container, edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("chat.composer")
    }
    private func bubble(_ message: Record) -> some View {
        let own = message["fromUserId"].string == session.user?.id
        return HStack(alignment: .top, spacing: 8) {
            if own { Spacer(minLength: 40) } else { NavigationLink { ProfileView(userID: peer.id) } label: { Avatar(user: peer, size: 42).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(peer.displayName + "的主页").accessibilityIdentifier("chat.avatar." + message.id) }
            VStack(alignment: own ? .trailing : .leading, spacing: 6) {
                if !own && session.chatShowSenderName {
                    Text(peer.displayName).font(.caption).foregroundStyle(PUBOTheme.secondary).lineLimit(2)
                        .accessibilityIdentifier("chat.sender." + message.id)
                }
                VStack(alignment: .leading, spacing: 7) {
                    if !message["recalledAt"].isNull { Text("消息已撤回").foregroundStyle(PUBOTheme.secondary) }
                    else {
                        if !message["replyTo"].isNull {
                            Button { if let id = message["replyToId"].string ?? message["replyTo"]["id"].string { Task { await openContext(id) } } } label: {
                                Label(ChatReferences.label(message["replyTo"]), systemImage: "arrowshape.turn.up.left").font(.caption).multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(6).background(PUBOTheme.divider.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).disabled(message["replyTo"]["unavailable"].bool || contextBusy).accessibilityIdentifier("chat.reference." + message.id)
                        }
                        if !message.text.isEmpty { ChatMessageContent(text: message.text, active: !searching && preview == nil && actionMessage == nil, identifier: "chat.text." + message.id, remoteEmojis: message["emojis"], menuActions: messageActions(message, own: own)).font(.system(size: messageFont)) }
                        ForEach(Record.list(message["attachments"])) { file in PrivateInlineAttachment(attachment: file, mediaActive: !searching && preview == nil && actionMessage == nil) { preview = PrivatePreviewItem(attachment: file, messageID: message.id) }.id(file.id + "-" + String(message["revision"].int)) }
                        if message["privateAttachmentFallback"].bool { Link("在本站网页查看此附件", destination: Endpoint.origin.appendingPathComponent("chat/messages/" + message.id)).font(.caption) }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 8)
                    .background(own ? PUBOTheme.ownBubble : PUBOTheme.panel, in: PUBOChatBubble(own: own))
                    .contextMenu { messageMenu(message, own: own) }
                if message["recalledAt"].isNull && !message["privateAttachmentFallback"].bool && !ChatContentPolicy.previewLinks(message.text).isEmpty {
                    ChatMessageLinkPreviews(text: message.text, active: !searching && preview == nil && actionMessage == nil, identifier: "chat.links." + message.id)
                }
                HStack(spacing: 6) {
                    if !own { Menu { messageMenu(message, own: own) } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("消息菜单").accessibilityIdentifier("chat.menu." + message.id) }
                    if let date = puboDate(message["createdAt"].string) { ChatRelativeTime(date: date) }
                    if own { Text(message["readState"].string == "read" ? "已读" : "已发送") }
                    if !message["editedAt"].isNull { Text("已编辑") }
                    if own { Menu { messageMenu(message, own: own) } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("消息菜单").accessibilityIdentifier("chat.menu." + message.id) }
                }.font(.caption2).foregroundStyle(PUBOTheme.secondary)
                if !message["reactions"].array.isEmpty && message["recalledAt"].isNull {
                    ChatReactionStrip(reactions: message["reactions"].array, ownUserID: session.user?.id ?? "", enabled: !own && !busy) { reaction, desired in Task { await toggleReaction(message, reaction, desired: desired) } }
                }
            }.task(id: "\(contextMode)-\(scenePhase == .active)-\(searching)") { if !own && !contextMode && !searching && scenePhase == .active { await markRead(message) } }
            if !own { Spacer(minLength: 28) }
        }
    }
    private func messageMenu(_ message: Record, own: Bool) -> some View {
        ChatMenuButtons(actions: messageActions(message, own: own))
    }
    private func messageActions(_ message: Record, own: Bool) -> [ChatMenuAction] {
        let epoch = session.generation
        let owner = session.user?.id
        func command(_ id: String, _ title: String, enabled: Bool = true, allowRecalled: Bool = false, _ perform: @escaping () -> Void) -> ChatMenuAction {
            ChatMenuAction(id: id, title: title, enabled: enabled) {
                guard active, scenePhase == .active, !searching, preview == nil, actionMessage == nil,
                      epoch == session.generation, owner == session.user?.id,
                      let current = messages.first(where: { $0.id == message.id }),
                      (allowRecalled || current["recalledAt"].isNull), current.raw == message.raw else { return }
                perform()
            }
        }
        var actions: [ChatMenuAction] = []
        if message["recalledAt"].isNull {
            actions.append(command("chat.reply." + message.id, "引用回复") { reply = message; saveDraft() })
            if !message.text.isEmpty { actions.append(command("chat.copy." + message.id, "复制文字") { UIPasteboard.general.string = message.text }) }
            let gifs = Record.list(message["attachments"]).filter { $0["mime"].string == "image/gif" }
            for (index, file) in gifs.enumerated() {
                actions.append(command("chat.collect." + message.id + "." + file.id, gifs.count == 1 ? "收藏表情包" : "收藏 GIF \(index + 1)", enabled: !stickerBusy) { collectSticker(file) })
            }
        }
        actions.append(command("chat.actions." + message.id, own ? "编辑／撤回消息" : "消息反应／举报", allowRecalled: true) { actionMessage = message })
        return actions
    }
    private func receive(_ event: ChatStreamEvent) {
        guard active, !event.room, event.targetID == peer.id, scenePhase == .active else { return }
        if event.kind == "message" {
            let row = Record(event.body)
            guard !row.id.isEmpty, Set([row["fromUserId"].string ?? "", row["toUserId"].string ?? ""]) == Set([peer.id, session.user?.id ?? ""]) else { return }
            if contextMode { hasNewer = true; return }
            if !messages.contains(where: { $0.id == row.id }) && !searching { animatedIDs.insert(row.id) }
            messages = Array(ChatRecords.merge(messages, [row]).suffix(2_000))
            if let author = session.user?.id { pending.removeAll { $0.matches(row, authorID: author) }; persist() }
        } else {
            // Private edits/reactions lack full payloads. Reuse the permission-checked state endpoint.
            if let id = event.messageID { session.changedChatIDs.insert(id) }
            Task { await load() }
        }
    }
    private func pendingBubble(_ item: PendingChat) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(item.text.isEmpty ? "[附件]" : item.text).padding(.horizontal, 12).padding(.vertical, 8).background(PUBOTheme.ownBubble, in: PUBOChatBubble(own: true))
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
    private func retryInitialLoad() async {
        if contextMode && messages.isEmpty, let initialMessageID { await openContext(initialMessageID) }
        else { await load() }
    }
    private func load(older: Bool = false, reconcileAll: Bool = false) async {
        // Initial deep links must load their target context, not report an empty
        // successful timeline from the intentionally skipped latest endpoint.
        if contextMode && messages.isEmpty && !older { return }
        if reconcileAll { needsFullState = true }
        guard active, !loading else { return }; loading = true; defer { loading = false }
        let epoch = syncEpoch
        retryOlder = older; loadError = nil
        do {
            var fields: [String: JSONValue] = ["userId": .string(peer.id), "limit": .number(50)]
            if older, let id = messages.first?.id { fields["untilId"] = .string(id) }
            let result = contextMode && !older ? [] : Record.list(try await session.call("chat/messages/user-timeline", fields))
            guard epoch == syncEpoch, !Task.isCancelled else { return }
            messages = Array(ChatRecords.merge(messages, result).suffix(2_000))
            if !contextMode || older { if older || messages.count <= 50 { hasMore = result.count == 50 && messages.count < 2_000 } }
            if let author = session.user?.id { pending.removeAll { item in result.contains { item.matches($0, authorID: author) } }; persist() }
            let all = needsFullState
            let ids = Array(Set((all ? messages.map(\.id) : []) + Array(session.changedChatIDs)).union(ChatReferences.ids(messages, draft: reply))).sorted()
            for offset in stride(from: 0, to: ids.count, by: 100) {
                let batch = Array(ids[offset..<min(offset + 100, ids.count)])
                let state = try await session.call("chat/messages/state", ["userId": .string(peer.id), "messageIds": .strings(batch)])
                guard epoch == syncEpoch, !Task.isCancelled else { return }
                guard case .array = state["messages"], case .array = state["missingIds"] else { throw APIError.invalidResponse }
                let updates = Record.list(state["messages"]).filter { batch.contains($0.id) }
                let missing = state["missingIds"].array.compactMap(\.string).filter { batch.contains($0) }
                let visible = Set(messages.map(\.id))
                messages = ChatRecords.merge(messages, updates.filter { visible.contains($0.id) }, missingIDs: missing)
                messages = ChatReferences.reconcile(messages, targets: updates, missing: missing)
                session.changedChatIDs.subtract(batch)
                updateDraft(targets: updates, missing: missing)
                if let preview, missing.contains(preview.messageID) || updates.contains(where: { $0.id == preview.messageID && !$0["recalledAt"].isNull }) { self.preview = nil }
            }
            if all { needsFullState = false }
            initialLoadCompleted = true; loadError = nil
        } catch {
            if active, epoch == syncEpoch, !Task.isCancelled { loadError = error.localizedDescription }
        }
    }
    private func updateDraft(targets: [Record], missing: [String]) {
        guard let reply else { return }
        if missing.contains(reply.id) || targets.contains(where: { $0.id == reply.id && !$0["recalledAt"].isNull }) {
            self.reply = nil; error = "引用的原消息已撤回或不可用，正文已保留。"; saveDraft()
        } else if let target = targets.first(where: { $0.id == reply.id && $0["revision"].int >= reply["revision"].int }) {
            self.reply = target; saveDraft()
        }
    }
    private func openContext(_ id: String) async {
        guard !contextBusy else { return }; contextBusy = true; defer { contextBusy = false }
        syncEpoch = UUID(); let epoch = syncEpoch; scrollTarget = nil
        if messages.isEmpty { loadError = nil }
        do {
            let value = try await session.call("chat/messages/context", ["userId": .string(peer.id), "messageId": .string(id)])
            guard epoch == syncEpoch, !Task.isCancelled else { return }
            let rows = Record.list(value["messages"])
            guard rows.contains(where: { $0.id == id }), rows.allSatisfy({ row in
                Set([row["fromUserId"].string ?? "", row["toUserId"].string ?? ""]) == Set([peer.id, ownerID ?? ""]) && row["toRoomId"].isNull
            }) else { throw APIError.invalidResponse }
            contextMode = true; messages = ChatRecords.merge([], rows); hasMore = value["hasOlder"].bool; hasNewer = value["hasNewer"].bool
            highlightedID = id; error = nil; initialLoadCompleted = true; loadError = nil
            await Task.yield(); guard epoch == syncEpoch else { return }; scrollTarget = id
        } catch {
            if active, epoch == syncEpoch, !Task.isCancelled {
                let message = "无法定位原消息：" + error.localizedDescription
                if messages.isEmpty { loadError = message } else { self.error = message }
            }
        }
    }
    private func returnToLatest() async {
        guard !contextBusy else { return }; contextBusy = true; defer { contextBusy = false }
        syncEpoch = UUID(); let epoch = syncEpoch
        do {
            let rows = Record.list(try await session.call("chat/messages/user-timeline", ["userId": .string(peer.id), "limit": .number(50)]))
            guard epoch == syncEpoch, !Task.isCancelled else { return }
            messages = ChatRecords.merge([], rows); contextMode = false; hasNewer = false; highlightedID = nil; hasMore = rows.count == 50; error = nil; initialLoadCompleted = true; loadError = nil
            scrollTarget = nil; await Task.yield(); scrollTarget = "bottom"
        } catch { if epoch == syncEpoch { self.error = error.localizedDescription } }
    }
    private func refreshPeer() async {
        do {
            let value = Record(try await session.call("users/show", ["userId": .string(peer.id)]))
            guard !Task.isCancelled, value.id == peer.id else { return }
            refreshedPeer = value
        } catch { /* Preserve last-known policy; server checks every send. */ }
    }
    private func sendNew() async {
        if let chatProblem { error = chatProblem; return }
        guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        if let sendProblem { error = sendProblem; saveDraft(); return }
        let item = PendingChat(recipientID: peer.id, text: text, attachmentIDs: attachments.map(\.id), replyToID: reply?.id)
        pending.append(item)
        guard persist() else { pending.removeAll { $0.id == item.id }; return }
        text = ""; attachments = []; reply = nil; stickerNotice = nil; saveDraft()
        await send(item)
    }
    private func send(_ original: PendingChat) async {
        if let chatProblem { error = chatProblem; return }
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
        do { _ = try await session.call("chat/messages/read", ["userId": .string(peer.id), "messageIds": .strings([message.id])], mutation: true); await session.refreshUnread() } catch { }
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
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "文件超过 50 MiB。") }
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
    private func collectSticker(_ attachment: Record) {
        guard !stickerBusy, let account = session.user?.id, let credential = session.token else { return }
        let epoch = session.generation; stickerBusy = true; stickerNotice = nil
        stickerTask = Task { @MainActor in
            defer { stickerBusy = false }
            do {
                guard attachment["size"].int <= GIFStickerCodec.inputLimit else { throw GIFStickerError.tooLarge }
                let original = try await session.api.privateAttachment(id: attachment.id, token: credential)
                let prepared = try await GIFStickerCodec.prepare(original)
                try Task.checkCancellation()
                guard epoch == session.generation, account == session.user?.id, scenePhase == .active else { return }
                guard let vault = session.gifStickers else { throw GIFStickerError.unavailable }
                let result = try vault.add(prepared, account: account)
                stickerNotice = result.inserted ? (prepared.wasCompressed ? "已自动压缩并收藏 · \(prepared.data.count / 1000)KB" : "已收藏表情包") : "已经收藏过这张表情包"
            } catch is CancellationError { }
            catch { if epoch == session.generation { stickerNotice = error.localizedDescription } }
        }
    }
    private func attachSticker(_ data: Data) async {
        guard !busy, attachments.count < 10, data.count <= GIFStickerCodec.byteLimit else { return }
        let epoch = session.generation; busy = true; defer { busy = false }
        do {
            let file = try await session.upload(data: data, name: "PUBO-sticker.gif", mime: "image/gif", peer: peer.id)
            guard epoch == session.generation, !Task.isCancelled else { return }
            attachments.append(file); saveDraft(); stickerNotice = "表情包已添加，点击发送即可"
        } catch { if epoch == session.generation { self.error = error.localizedDescription } }
    }
    private func loadConversation() async {
        let owner = session.generation
        do { let value = try await session.call("chat/conversation-settings/show", ["userId": .string(peer.id)]); guard owner == session.generation, !Task.isCancelled else { return }; conversationSettings = value } catch { }
    }
    private func updateConversation(_ key: String, _ value: Bool) async {
        guard !settingBusy else { return }; settingBusy = true; defer { settingBusy = false }
        do {
            do { _ = try await session.call("chat/conversation-settings/update", ["userId": .string(peer.id), key: .bool(value)], mutation: true) }
            catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            await loadConversation(); await session.refreshUnread()
            let confirmed = key == "pinned" ? !conversationSettings["pinnedAt"].isNull : conversationSettings["isMuted"].bool
            error = confirmed == value ? nil : "设置结果待确认，请刷新后核对。"
        } catch { self.error = error.localizedDescription }
    }
    private func toggleReaction(_ message: Record, _ reaction: String, desired: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let generation = session.generation, viewer = session.user?.id
        let key = SocialContent.chatReactionKey(reaction)
        func mine(_ row: Record) -> Bool { row["reactions"].array.contains { $0["user"]["id"].string == viewer && SocialContent.chatReactionKey($0["reaction"].string ?? "") == key } }
        do {
            let current = Record(try await session.call("chat/messages/show", ["messageId": .string(message.id)]))
            guard current["recalledAt"].isNull, current["fromUserId"].string != session.user?.id else { return }
            if mine(current) == desired { messages = ChatRecords.merge(messages, [current]); error = nil; return }
            _ = try await session.call(desired ? "chat/messages/react" : "chat/messages/unreact", ["messageId": .string(message.id), "reaction": .string(reaction)], mutation: true)
            let updated = Record(try await session.call("chat/messages/show", ["messageId": .string(message.id)]))
            guard mine(updated) == desired else { throw APIError.uncertain }
            guard generation == session.generation, active else { return }; messages = ChatRecords.merge(messages, [updated]); error = nil
        } catch {
            let issue = error
            guard generation == session.generation, active else { return }
            if let value = try? await session.call("chat/messages/show", ["messageId": .string(message.id)]), mine(Record(value)) == desired, !value["id"].isNull, generation == session.generation, active {
                messages = ChatRecords.merge(messages, [Record(value)]); self.error = nil
            } else if generation == session.generation, active { self.error = issue.localizedDescription; await load(reconcileAll: true) }
        }
    }
    private func voice() async {
        guard !busy, attachments.count < 10 else { return }
        do {
            if recorder.recording { busy = true; defer { busy = false }; let data = try recorder.finish(); attachments.append(try await session.upload(data: data, name: "语音.m4a", mime: "audio/mp4", peer: peer.id, voice: true)); saveDraft() }
            else { session.activeVoiceAttachmentID = nil; try await recorder.start() }
        } catch { self.error = error.localizedDescription }
    }
}

struct ChatDraft: Codable { let text: String; let attachments: [Record]; var reply: Record?; var lastFailure: String? }
struct PrivatePreviewItem: Identifiable { var id: String { attachment.id }; let attachment: Record; let messageID: String }

struct PrivateAttachmentView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let attachment: Record
    @State private var data: Data?
    @State private var localURL: URL?
    @State private var error: String?
    @State private var gifImage: SDAnimatedImage?
    @State private var imagePreviewDisabled = false
    var body: some View {
        NavigationStack {
            Group {
                if let error { ErrorBanner(message: error) }
                else if let data, let localURL { AttachmentPreviewContent(data: data, url: localURL, mime: attachment["mime"].string ?? "application/octet-stream", name: attachment["name"].string ?? "私信附件", gifImage: gifImage, imagePreviewDisabled: imagePreviewDisabled) }
                else { ProgressView("正在验证附件权限…") }
            }.puboScreen().navigationTitle(attachment["name"].string ?? "私信附件").navigationBarTitleDisplayMode(.inline).toolbar { Button("关闭") { dismiss() } }
                .task(id: "\(session.generation)-\(scenePhase == .active)") {
                    clear(); error = nil
                    guard scenePhase == .active else { return }
                    do {
                        guard let token = session.token else { throw APIError.invalidResponse }
                        guard attachment["size"].int <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "附件超过首版 50 MB 预览上限，请在网页打开。") }
                        let epoch = session.generation
                        let content = try await session.api.privateAttachment(id: attachment.id, token: token)
                        guard epoch == session.generation, !Task.isCancelled else { return }
                        var decoded: SDAnimatedImage?
                        var previewDisabled = false
                        if PrivateImageDecoder.isGIF(content) {
                            do { decoded = try await PrivateImageDecoder.decode(content, maxPixel: 1280) as? SDAnimatedImage }
                            catch { previewDisabled = true }
                        }
                        guard epoch == session.generation, scenePhase == .active, !Task.isCancelled else { return }
                        let ext = UTType(mimeType: attachment["mime"].string ?? "")?.preferredFilenameExtension ?? "bin"
                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pubo-private-\(UUID().uuidString).\(ext)")
                        try content.write(to: file, options: [.atomic, .completeFileProtection])
                        gifImage = decoded; imagePreviewDisabled = previewDisabled; localURL = file; data = content
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }.onDisappear { clear() }
        }
    }
    private func clear() { data = nil; gifImage = nil; imagePreviewDisabled = false; if let localURL { try? FileManager.default.removeItem(at: localURL) }; localURL = nil }
}

