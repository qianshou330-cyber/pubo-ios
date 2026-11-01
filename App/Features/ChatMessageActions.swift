import SwiftUI
import PUBOCore

private struct MessageEditDraft: Codable {
    var text: String
    var revision: Int
    var uncertain = false
}

struct ChatMessageActions: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let message: Record
    let peerID: String
    let ownerID: String
    let updated: (Record) -> Void
    @State private var current: Record?
    @State private var draft: MessageEditDraft?
    @State private var busy = false
    @State private var error: String?
    @State private var feedback: String?
    @State private var confirmRecall = false
    @State private var reactionPicker = false
    @State private var reporting = false
    @State private var loaded = false
    private var shown: Record { current ?? message }
    private var own: Bool { shown["fromUserId"].string == session.user?.id }
    private var alive: Bool { shown["recalledAt"].isNull }
    private var canEdit: Bool { own && alive && !shown.text.isEmpty && shown["attachments"].array.isEmpty && shown["fileId"].isNull && (shown["createdAt"].string.flatMap(SocialContent.date).map { Date().timeIntervalSince($0) < 86_400 } ?? false) }
    private var key: String { "chat-edit-" + message.id }
    private var myReactions: [String] { Array(Set(shown["reactions"].array.filter { $0["user"]["id"].string == session.user?.id }.compactMap { $0["reaction"].string })).sorted() }
    var body: some View {
        NavigationStack {
            Form {
                Section("服务器当前消息") { Text(alive ? shown.text : "消息已撤回"); if !shown["editedAt"].isNull { Text("已编辑 · 版本 \(shown["revision"].int)").font(.caption) } }
                if let draft {
                    Section("我的编辑") {
                        TextEditor(text: Binding(get: { self.draft?.text ?? "" }, set: { self.draft?.text = $0; saveDraft() })).frame(minHeight: 120).disabled(busy || draft.uncertain).accessibilityIdentifier("chat.edit.text")
                        if draft.uncertain { Text("上次编辑结果待确认。先核对服务器消息，不会自动重发。").font(.footnote) }
                        if canEdit && !draft.uncertain && draft.revision == shown["revision"].int {
                            Button("保存编辑") { Task { await edit() } }.disabled(busy || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("chat.edit.save")
                        } else if canEdit && loaded {
                            Button("以当前版本继续编辑") { self.draft?.revision = shown["revision"].int; self.draft?.uncertain = false; saveDraft() }.disabled(busy)
                        }
                        Button("放弃这份编辑", role: .destructive) { self.draft = nil; saveDraft() }.disabled(busy)
                    }
                } else if canEdit { Button("编辑文字") { draft = MessageEditDraft(text: shown.text, revision: shown["revision"].int); saveDraft() }.disabled(!loaded || busy) }
                if alive && own { Button("撤回消息", role: .destructive) { confirmRecall = true }.disabled(!loaded || busy) }
                if alive && !own {
                    Section("表情反应") {
                        Button("添加反应") { reactionPicker = true }.disabled(!loaded || busy)
                        ForEach(myReactions, id: \.self) { reaction in Button("取消 " + reaction) { Task { await react(reaction, remove: true) } }.disabled(busy).accessibilityIdentifier("chat.reaction.remove." + SocialContent.chatReactionKey(reaction)) }
                    }
                }
                if !own { Button("举报这条私信") { reporting = true } }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("chat.action.error") }
                if let feedback { Text(feedback).foregroundStyle(.secondary) }
                Button("核对最新状态") { Task { await refresh() } }.disabled(busy)
            }.puboForm().navigationTitle("消息操作").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
                .task {
                    if !loaded {
                        if let account = session.user?.id { draft = (try? session.store?.read(MessageEditDraft.self, account: account, key: key)) ?? nil }
                        await refresh()
                    }
                }
                .sheet(isPresented: $reactionPicker) { ReactionPicker { reaction in Task { await react(reaction, remove: false) } } }
                .sheet(isPresented: $reporting) { ReportView(userID: peerID, context: "私信消息：" + Endpoint.origin.appendingPathComponent("chat/messages/" + message.id).absoluteString) }
                .confirmationDialog("撤回后对方将不能继续读取这条消息及其附件。", isPresented: $confirmRecall) { Button("撤回消息", role: .destructive) { Task { await recall() } } }
        }.interactiveDismissDisabled(busy).onDisappear { saveDraft() }
    }
    @discardableResult private func saveDraft() -> Bool {
        guard session.user?.id == ownerID else { return false }
        if session.testMode { return true }
        guard let owner = session.user?.id, let store = session.store else { error = "本机存储不可用，暂时不能安全编辑。"; return false }
        do { try store.save(draft, account: owner, key: key); return true }
        catch { self.error = "编辑草稿保存失败，请不要关闭页面。"; return false }
    }
    private func fetch() async throws -> Record {
        guard session.user?.id == ownerID else { throw CancellationError() }
        let value = Record(try await session.call("chat/messages/show", ["messageId": .string(message.id)]))
        let users = Set([value["fromUserId"].string ?? "", value["toUserId"].string ?? ""])
        guard value.id == message.id, users == Set([session.user?.id ?? "", peerID]) else { throw APIError.invalidResponse }
        current = ChatRecords.merge([shown], [value]).first; loaded = true
        updated(current ?? value)
        return current ?? value
    }
    private func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        feedback = nil
        do {
            let value = try await fetch()
            if let draft, draft.uncertain && value["revision"].int > draft.revision && value.text == draft.text.trimmingCharacters(in: .whitespacesAndNewlines) { self.draft = nil; saveDraft(); error = nil; feedback = "已核对，编辑已生效。" }
            else { error = nil }
        } catch { self.error = error.localizedDescription }
    }
    private func edit() async {
        guard !busy, let draft, !draft.uncertain, canEdit else { return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && text.unicodeScalars.count <= 2_000 else { error = "消息需要 1～2000 个字符。"; return }
        busy = true; defer { busy = false }
        feedback = nil
        self.draft?.uncertain = true
        guard saveDraft() else { self.draft?.uncertain = false; return }
        do {
            let result = Record(try await session.call("chat/messages/update", ["messageId": .string(message.id), "text": .string(text), "expectedRevision": .number(Double(draft.revision))], mutation: true))
            guard result.id == message.id, result.text == text, result["revision"].int == draft.revision + 1, result["recalledAt"].isNull else { throw APIError.uncertain }
            current = ChatRecords.merge([shown], [result]).first; if let current { updated(current) }
            self.draft = nil; saveDraft(); error = nil; feedback = "编辑已保存。"
        } catch {
            if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { self.draft?.uncertain = false; saveDraft() }
            self.error = error.localizedDescription
            // Read only: never silently rebase a conflicting edit or retry an uncertain write.
            _ = try? await fetch()
        }
    }
    private func recall() async {
        guard !busy, own, alive else { return }; busy = true; defer { busy = false }
        feedback = nil
        do {
            let before = try await fetch()
            if before["recalledAt"].isNull { _ = try await session.call("chat/messages/delete", ["messageId": .string(message.id)], mutation: true) }
            _ = try await fetch(); error = alive ? "撤回结果尚未确认，请核对最新状态。" : nil; feedback = alive ? nil : "已撤回。"
        } catch { self.error = error.localizedDescription; _ = try? await fetch() }
    }
    private func react(_ reaction: String, remove: Bool) async {
        guard !busy, !own, alive else { return }; busy = true; defer { busy = false }
        do {
            _ = try await fetch()
            guard alive else { return }
            let exists = myReactions.contains { SocialContent.chatReactionKey($0) == SocialContent.chatReactionKey(reaction) }
            if exists == remove { _ = try await session.call(remove ? "chat/messages/unreact" : "chat/messages/react", ["messageId": .string(message.id), "reaction": .string(reaction)], mutation: true) }
            _ = try await fetch(); error = nil
        } catch { self.error = error.localizedDescription; _ = try? await fetch() }
    }
}
