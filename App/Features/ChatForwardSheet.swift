import SwiftUI
import PUBOCore

struct ChatForwardPayload: Identifiable {
    let id = UUID()
    let messages: [Record]
}

/// Friend picker and idempotent forwarding executor for 1-on-1 private chat messages (up to 10 messages).
/// Private attachments are always re-fetched under the viewer's credential and re-uploaded scoped to the target `toUserId`.
struct ChatForwardSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let messages: [Record]
    let sourcePeer: Record
    let onComplete: (String) -> Void

    @State private var mode: ChatForwardMode = .oneByOne
    @State private var query = ""
    @State private var recentFriends: [Record] = []
    @State private var followingFriends: [Record] = []
    @State private var searchResults: [Record] = []
    @State private var loadingFriends = false
    @State private var searchingRemote = false
    @State private var loadError: String?

    @State private var confirmRecipient: Record?
    @State private var sending = false
    @State private var cancelRequested = false
    @State private var progressCurrent = 0
    @State private var progressTotal = 0
    @State private var resultBanner: ForwardResultBanner?
    @State private var forwardTask: Task<Void, Never>?

    private struct ForwardResultBanner {
        let isError: Bool
        let title: String
        let detail: String?
    }

    private var aliveMessages: [Record] {
        Array(messages.filter { $0["recalledAt"].isNull }.prefix(ChatSelectionState.maxSelectionCount))
    }

    private var attachmentSummary: ChatForwardAttachmentSummary {
        ChatForwardPlanner.inspectAttachments(in: aliveMessages)
    }

    private var combinedValidation: Result<String, ChatForwardError> {
        ChatForwardPlanner.buildCombinedText(
            messages: aliveMessages,
            peerName: sourcePeer.displayName,
            viewerID: session.user?.id,
            viewerName: session.user?.displayName ?? "我"
        )
    }

    private var combinedProblem: String? {
        guard mode == .combined else { return nil }
        if case .failure(let error) = combinedValidation { return error.localizedDescription }
        return nil
    }

    private var filteredLocal: (recent: [Record], following: [Record]) {
        ChatForwardPlanner.deduplicateRecipients(
            recent: recentFriends,
            following: followingFriends,
            viewerID: session.user?.id,
            query: query
        )
    }

    private var filteredRemote: [Record] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let localIDs = Set(filteredLocal.recent.map(\.id) + filteredLocal.following.map(\.id))
        return searchResults.filter { user in
            !user.id.isEmpty && user.id != session.user?.id && !localIDs.contains(user.id)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if let resultBanner {
                    resultSection(resultBanner)
                }
                if sending {
                    progressSection
                }
                if let loadError {
                    Section {
                        ErrorBanner(message: loadError) { Task { await loadCandidates() } }
                    }.listRowBackground(PUBOTheme.panel)
                }
                searchFieldSection
                if loadingFriends && recentFriends.isEmpty && followingFriends.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在加载好友列表…").font(.callout)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.listRowBackground(PUBOTheme.panel)
                } else {
                    if !filteredLocal.recent.isEmpty {
                        Section("最近联系") {
                            ForEach(filteredLocal.recent) { user in recipientRow(user) }
                        }.listRowBackground(PUBOTheme.panel)
                    }
                    if !filteredLocal.following.isEmpty {
                        Section("我关注的好友") {
                            ForEach(filteredLocal.following) { user in recipientRow(user) }
                        }.listRowBackground(PUBOTheme.panel)
                    }
                    if !filteredRemote.isEmpty {
                        Section("站内搜索结果") {
                            ForEach(filteredRemote) { user in recipientRow(user) }
                        }.listRowBackground(PUBOTheme.panel)
                    } else if searchingRemote {
                        Section("站内搜索结果") {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在搜索站内好友…").font(.caption).foregroundStyle(PUBOTheme.secondary)
                            }
                        }.listRowBackground(PUBOTheme.panel)
                    }
                    if !loadingFriends && !searchingRemote && filteredLocal.recent.isEmpty && filteredLocal.following.isEmpty && filteredRemote.isEmpty {
                        Section {
                            Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无可转发的好友，可先关注好友或输入用户名搜索。" : "未找到匹配的好友。")
                                .font(.callout)
                                .foregroundStyle(PUBOTheme.secondary)
                                .accessibilityIdentifier("chat.forward.empty")
                        }.listRowBackground(PUBOTheme.panel)
                    }
                }
            }
            .puboList()
            .navigationTitle("转发给好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(resultBanner != nil ? "完成" : "取消") {
                        dismiss()
                    }
                    .disabled(sending)
                    .accessibilityIdentifier("chat.forward.close")
                }
            }
            .interactiveDismissDisabled(sending)
            .task { await loadCandidates() }
            .task(id: query) { await searchRemoteIfNeeded() }
            .onChange(of: session.generation) { _, _ in
                forwardTask?.cancel()
                dismiss()
            }
            .onDisappear {
                forwardTask?.cancel()
            }
            .alert(
                "确认转发给 \(confirmRecipient?.displayName ?? "好友")？",
                isPresented: Binding(get: { confirmRecipient != nil }, set: { if !$0 { confirmRecipient = nil } })
            ) {
                if let target = confirmRecipient {
                    Button("确认转发") {
                        confirmRecipient = nil
                        startForwarding(to: target)
                    }
                    .accessibilityIdentifier("chat.forward.confirm")
                }
                Button("取消", role: .cancel) { confirmRecipient = nil }
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    private var confirmationMessage: String {
        if mode == .combined && aliveMessages.count > 1 {
            return "将把所选 \(aliveMessages.count) 条消息合并为 1 条文字记录发送。"
        }
        if attachmentSummary.hasForwardableAttachments {
            return "将按时间顺序逐条发送 \(aliveMessages.count) 条消息（含 \(attachmentSummary.forwardableCount) 个附件重新加密传输）。"
        }
        return "将按时间顺序逐条发送 \(aliveMessages.count) 条消息。"
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("已选 \(aliveMessages.count) 条消息（上限 \(ChatSelectionState.maxSelectionCount) 条）", systemImage: "arrowshape.turn.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PUBOTheme.text)
                    Spacer()
                }
                if aliveMessages.count > 1 {
                    Picker("转发方式", selection: $mode) {
                        ForEach(ChatForwardMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(sending)
                    .accessibilityIdentifier("chat.forward.mode")
                }
                if mode == .oneByOne {
                    if attachmentSummary.hasForwardableAttachments {
                        Text("包含 \(attachmentSummary.forwardableCount) 个私信附件，转发时将重新加密上传至目标好友会话。")
                            .font(.caption)
                            .foregroundStyle(PUBOTheme.secondary)
                    }
                    if attachmentSummary.oversizeCount > 0 {
                        Text("有 \(attachmentSummary.oversizeCount) 个超过 50 MiB 的附件无法在 App 内转存，将自动跳过。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if attachmentSummary.fallbackCount > 0 {
                        Text("有 \(attachmentSummary.fallbackCount) 条网页回退附件消息无法直接转存附件，仅转发可用正文。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    if let combinedProblem {
                        Text(combinedProblem)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("chat.forward.combinedError")
                    } else if attachmentSummary.totalAttachments > 0 {
                        Text("合并文字模式仅发送文本与附件占位摘要；如需完整转发图片/语音/文件，请切换到「逐条转发」。")
                            .font(.caption)
                            .foregroundStyle(PUBOTheme.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("转发摘要")
        } footer: {
            Text("为保护私信附件隐私，仅支持转发给本站好友私信。")
        }
        .listRowBackground(PUBOTheme.panel)
    }

    private var searchFieldSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PUBOTheme.secondary)
                    .accessibilityHidden(true)
                TextField("搜索好友昵称或用户名", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(sending)
                    .accessibilityIdentifier("chat.forward.search")
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PUBOTheme.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
        }
        .listRowBackground(PUBOTheme.panel)
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在转发 \(progressCurrent) / \(max(1, progressTotal))…")
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("chat.forward.progress")
                }
                Button("停止剩余转发", role: .destructive) {
                    cancelRequested = true
                }
                .disabled(cancelRequested)
                .font(.caption)
                .accessibilityIdentifier("chat.forward.stop")
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(PUBOTheme.panel)
    }

    private func resultSection(_ banner: ForwardResultBanner) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(banner.title, systemImage: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(banner.isError ? .red : PUBOTheme.accent)
                if let detail = banner.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(PUBOTheme.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("chat.forward.result")
        }
        .listRowBackground(PUBOTheme.panel)
    }

    @ViewBuilder
    private func recipientRow(_ user: Record) -> some View {
        let problem = ChatForwardPlanner.eligibleRecipientProblem(
            account: session.user,
            viewerID: session.user?.id,
            recipient: user
        )
        let disabled = sending || problem != nil || combinedProblem != nil || aliveMessages.isEmpty
        Button {
            resultBanner = nil
            confirmRecipient = user
        } label: {
            HStack(spacing: 12) {
                Avatar(user: user, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.body)
                            .foregroundStyle(disabled ? PUBOTheme.secondary : PUBOTheme.text)
                            .lineLimit(1)
                        if user.id == sourcePeer.id {
                            Text("当前会话")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PUBOTheme.button, in: Capsule())
                                .foregroundStyle(PUBOTheme.secondary)
                        }
                    }
                    if let handle = FolloweeDisplayHandle.text(for: user) {
                        Text(verbatim: handle)
                            .font(.caption)
                            .foregroundStyle(PUBOTheme.secondary)
                            .lineLimit(1)
                    }
                    if let problem {
                        Text(problem)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if !disabled {
                    Image(systemName: "paperplane")
                        .font(.subheadline)
                        .foregroundStyle(PUBOTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("chat.forward.recipient." + user.id)
    }

    private func loadCandidates() async {
        guard !loadingFriends, let viewer = session.user else { return }
        let epoch = session.generation
        loadingFriends = true
        loadError = nil
        defer { loadingFriends = false }

        async let ordinary = fetchConversations(pinned: false, limit: 30)
        async let pinned = fetchConversations(pinned: true, limit: 10)
        async let followingResult = fetchFollowing(userID: viewer.id)

        let (ordRows, pinRows, folOutcome) = await (ordinary, pinned, followingResult)
        guard epoch == session.generation, !Task.isCancelled else { return }

        var recent: [Record] = []
        for raw in pinRows + ordRows {
            let user = Record(raw["user"])
            if !user.id.isEmpty { recent.append(user) }
        }
        recentFriends = recent

        switch folOutcome {
        case .success(let rows):
            followingFriends = rows.compactMap { row in
                let user = Record(row["followee"])
                return user.id.isEmpty ? nil : user
            }
        case .failure(let error):
            if recent.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }

    private func fetchConversations(pinned: Bool, limit: Int) async -> [JSONValue] {
        do {
            let value = try await session.call("chat/conversations", ["limit": .number(Double(limit)), "pinned": .bool(pinned)])
            return value.array
        } catch {
            return []
        }
    }

    private func fetchFollowing(userID: String) async -> Result<[JSONValue], Error> {
        do {
            let value = try await session.call("users/following", ["userId": .string(userID), "limit": .number(50)])
            guard case .array = value else { throw APIError.invalidResponse }
            return .success(value.array)
        } catch {
            return .failure(error)
        }
    }

    private func searchRemoteIfNeeded() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            searchingRemote = false
            return
        }
        let epoch = session.generation
        searchingRemote = true
        defer { searchingRemote = false }
        do {
            try await Task.sleep(for: .milliseconds(300))
            guard epoch == session.generation, !Task.isCancelled else { return }
            let found = Record.list(try await session.call(
                "users/search",
                ["query": .string(String(trimmed.prefix(100))), "origin": .string("local"), "limit": .number(20)]
            ))
            guard epoch == session.generation, !Task.isCancelled else { return }
            searchResults = found
        } catch {
            if epoch == session.generation, !Task.isCancelled {
                searchResults = []
            }
        }
    }

    private func startForwarding(to recipient: Record) {
        guard !sending else { return }
        let items = aliveMessages
        guard !items.isEmpty else {
            resultBanner = ForwardResultBanner(isError: true, title: "没有可转发的消息", detail: "所选消息均已撤回。")
            return
        }
        if let problem = ChatForwardPlanner.eligibleRecipientProblem(account: session.user, viewerID: session.user?.id, recipient: recipient) {
            resultBanner = ForwardResultBanner(isError: true, title: "无法转发给 \(recipient.displayName)", detail: problem)
            return
        }

        let epoch = session.generation
        sending = true
        cancelRequested = false
        resultBanner = nil

        forwardTask = Task { @MainActor in
            defer { sending = false }
            if mode == .combined && items.count > 1 {
                await forwardCombined(items, to: recipient, epoch: epoch)
            } else {
                await forwardOneByOne(items, to: recipient, epoch: epoch)
            }
        }
    }

    private func forwardCombined(_ items: [Record], to recipient: Record, epoch: UUID) async {
        progressTotal = 1
        progressCurrent = 1
        switch ChatForwardPlanner.buildCombinedText(
            messages: items,
            peerName: sourcePeer.displayName,
            viewerID: session.user?.id,
            viewerName: session.user?.displayName ?? "我"
        ) {
        case .failure(let error):
            resultBanner = ForwardResultBanner(isError: true, title: "合并转发失败", detail: error.localizedDescription)
        case .success(let text):
            do {
                let pending = PendingChat(recipientID: recipient.id, text: text)
                let sent = Record(try await session.call("chat/messages/create-to-user", pending.payload, mutation: true))
                guard epoch == session.generation else { return }
                guard !sent.id.isEmpty else { throw APIError.uncertain }
                onComplete("已合并转发 \(items.count) 条消息给 \(recipient.displayName)")
                dismiss()
            } catch {
                guard epoch == session.generation else { return }
                resultBanner = ForwardResultBanner(isError: true, title: "合并转发未完成", detail: error.localizedDescription)
            }
        }
    }

    private func forwardOneByOne(_ items: [Record], to recipient: Record, epoch: UUID) async {
        progressTotal = items.count
        progressCurrent = 0

        var sentCount = 0
        var skippedCount = 0
        var failedCount = 0
        var failureReasons: [String] = []
        let fatalCodes: Set<String> = [
            "CHAT_FIRST_MESSAGE_TEXT_ONLY",
            "CHAT_REPLY_REQUIRED",
            "YOU_HAVE_BEEN_BLOCKED",
            "RECIPIENT_IS_YOURSELF",
            "PERMISSION_DENIED"
        ]

        for (index, message) in items.enumerated() {
            if cancelRequested || Task.isCancelled || epoch != session.generation {
                skippedCount += items.count - index
                break
            }
            progressCurrent = index + 1
            do {
                var newAttachmentIDs: [String] = []
                let sourceAttachments = Record.list(message["attachments"])
                if !sourceAttachments.isEmpty {
                    guard let token = session.token else {
                        throw APIError(code: "CREDENTIAL_REQUIRED", message: "请先登录。")
                    }
                    for attachment in sourceAttachments {
                        if cancelRequested || Task.isCancelled || epoch != session.generation {
                            throw CancellationError()
                        }
                        guard attachment["size"].int <= ChatForwardPlanner.maxAttachmentBytes else {
                            continue
                        }
                        let rawData = try await session.api.privateAttachment(id: attachment.id, token: token)
                        guard epoch == session.generation, !Task.isCancelled else { throw CancellationError() }
                        let filename = attachment["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "PUBO-forward.bin"
                        let mime = attachment["mime"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream"
                        let isVoice = attachment["kind"].string == "voice"
                        let uploaded = try await session.upload(
                            data: rawData,
                            name: filename,
                            mime: mime,
                            peer: recipient.id,
                            voice: isVoice
                        )
                        guard !uploaded.id.isEmpty else { throw APIError.uncertain }
                        newAttachmentIDs.append(uploaded.id)
                    }
                }

                let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty && newAttachmentIDs.isEmpty {
                    skippedCount += 1
                    continue
                }

                let pending = PendingChat(
                    recipientID: recipient.id,
                    text: trimmedText,
                    attachmentIDs: newAttachmentIDs
                )
                let sent = Record(try await session.call("chat/messages/create-to-user", pending.payload, mutation: true))
                guard epoch == session.generation else { return }
                guard !sent.id.isEmpty else { throw APIError.uncertain }
                sentCount += 1
            } catch is CancellationError {
                skippedCount += items.count - index
                break
            } catch {
                failedCount += 1
                let reason = error.localizedDescription
                if !failureReasons.contains(reason) { failureReasons.append(reason) }
                if let code = (error as? APIError)?.code, fatalCodes.contains(code) {
                    skippedCount += max(0, items.count - index - 1)
                    break
                }
            }
        }

        guard epoch == session.generation else { return }
        if failedCount == 0 && skippedCount == 0 && !cancelRequested {
            onComplete("已转发 \(sentCount) 条消息给 \(recipient.displayName)")
            dismiss()
            return
        }

        var parts: [String] = []
        if sentCount > 0 { parts.append("已转发 \(sentCount) 条") }
        if skippedCount > 0 { parts.append("跳过/停止 \(skippedCount) 条") }
        if failedCount > 0 { parts.append("失败 \(failedCount) 条") }
        let title = parts.isEmpty ? "转发未完成" : parts.joined(separator: "，")
        let detail = failureReasons.isEmpty ? nil : failureReasons.joined(separator: "；")
        resultBanner = ForwardResultBanner(isError: failedCount > 0 || sentCount == 0, title: title, detail: detail)
    }
}
