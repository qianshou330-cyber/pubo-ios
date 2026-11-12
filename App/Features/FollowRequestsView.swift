import SwiftUI
import PUBOCore

private struct FollowRequestConfirmation: Identifiable {
    let row: Record
    let user: Record
    let decision: FollowRequestDecision
    let direction: FollowRequestDirection
    let generation: UUID
    var id: String { row.id + decision.rawValue }
}

struct FollowRequestsView: View {
    @Environment(AppSession.self) private var session
    @State private var direction = FollowRequestDirection.received
    @State private var page = FollowRequestPage()
    @State private var initializedGeneration: UUID?
    @State private var visible = true
    @State private var error: String?
    @State private var busy = false
    @State private var acting: String?
    @State private var uncertainIDs = Set<String>()
    @State private var confirmation: FollowRequestConfirmation?
    @State private var requestID = UUID()
    @State private var mutationID = UUID()
    var body: some View {
        List {
            Picker("申请类型", selection: $direction) {
                ForEach(FollowRequestDirection.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(acting != nil).accessibilityIdentifier("followRequests.direction")
            if busy {
                HStack(spacing: 12) {
                    ProgressView().accessibilityHidden(true)
                    Text("正在加载关注申请…").font(.callout)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在加载关注申请…")
                .accessibilityIdentifier("followRequests.loading")
            }
            ForEach(page.rows) { row in
                let user = Record(row[direction.userKey])
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink { ProfileView(userID: user.id) } label: {
                        HStack { Avatar(user: user); VStack(alignment: .leading) { Text(user.displayName); Text("@" + (user["username"].string ?? "")).font(.caption).foregroundStyle(.secondary) } }
                    }.buttonStyle(.plain)
                    HStack {
                        if direction == .received {
                            Button { Task { await respond(row, user: user, decision: .accept, source: .received, generation: session.generation) } } label: {
                                Text("接受").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }.accessibilityIdentifier("followRequests.accept." + row.id)
                            Spacer()
                            Button(role: .destructive) { confirmation = FollowRequestConfirmation(row: row, user: user, decision: .reject, direction: direction, generation: session.generation) } label: {
                                Text("拒绝").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }.accessibilityIdentifier("followRequests.reject." + row.id)
                        } else {
                            Button(role: .destructive) { confirmation = FollowRequestConfirmation(row: row, user: user, decision: .cancel, direction: direction, generation: session.generation) } label: {
                                Text("撤回申请").frame(minHeight: 44).contentShape(Rectangle())
                            }.accessibilityIdentifier("followRequests.cancel." + row.id)
                        }
                    // List's automatic row button behavior must not dispatch both actions or navigation.
                    }.buttonStyle(.borderless).disabled(acting != nil || uncertainIDs.contains(row.id))
                    if uncertainIDs.contains(row.id) { Text("结果待核对，请刷新后再操作。").font(.caption).foregroundStyle(.secondary) }
                }.accessibilityElement(children: .contain)
            }
            if page.rows.isEmpty && !busy && error == nil && !page.hasMore { Text("暂无关注申请").accessibilityIdentifier("followRequests.empty") }
            if page.hasMore {
                Button("加载更多") { Task { await load() } }.disabled(busy || acting != nil).accessibilityIdentifier("followRequests.more")
            }
            if let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }
        }.puboList().navigationTitle("关注申请")
            .toolbar {
                Button { Task { await load(reset: true) } } label: { Label("刷新申请", systemImage: "arrow.clockwise") }
                    .disabled(acting != nil).accessibilityIdentifier("followRequests.refresh")
            }
            .onAppear { visible = true }
            .onDisappear { visible = false; requestID = UUID(); busy = false; confirmation = nil }
            .task(id: direction.rawValue + session.generation.uuidString) {
                requestID = UUID(); busy = false
                page = FollowRequestPage(); error = nil; uncertainIDs = []; confirmation = nil
                if initializedGeneration != session.generation {
                    initializedGeneration = session.generation
                    mutationID = UUID(); acting = nil
                    let initial = FollowRequestDirection.initial(user: session.user?.raw ?? .null)
                    if direction != initial { direction = initial; return }
                }
                await load(reset: true)
            }
            .refreshable { await load(reset: true) }
            .alert(confirmation.map { $0.decision.title + "？" } ?? "确认操作", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { selected in
                Button("保留", role: .cancel) { confirmation = nil }.accessibilityIdentifier("followRequests.keep")
                Button(selected.decision.title, role: .destructive) { Task { await respond(selected.row, user: selected.user, decision: selected.decision, source: selected.direction, generation: selected.generation) } }.accessibilityIdentifier("followRequests.confirm")
            } message: { selected in
                Text((selected.decision == .reject ? "拒绝 " : "撤回发给 ") + selected.user.displayName + " 的关注申请？")
            }
    }
    private func load(reset: Bool = false) async {
        guard visible, acting == nil, reset || (!busy && page.hasMore) else { return }
        let attempt = UUID(), source = direction, accountID = session.user?.id, epoch = session.generation
        requestID = attempt; busy = true
        defer { if requestID == attempt { busy = false } }
        do {
            var fields: [String: JSONValue] = ["limit": .number(30)]
            if !reset, let cursor = page.cursor { fields["untilId"] = .string(cursor) }
            let response = try await session.call(source.endpoint, fields); try Task.checkCancellation()
            guard visible, requestID == attempt, direction == source, session.user?.id == accountID, session.generation == epoch else { return }
            guard case .array = response else { throw APIError.invalidResponse }
            let records = Record.list(response)
            guard records.count == response.array.count,
                  records.allSatisfy({ !$0.id.isEmpty && !Record($0[source.userKey]).id.isEmpty }) else { throw APIError.invalidResponse }
            page.apply(records, reset: reset, limit: 30)
            if reset { uncertainIDs = [] }
            error = nil
        } catch { if !Task.isCancelled && visible && requestID == attempt && direction == source && session.generation == epoch && session.user?.id == accountID { self.error = error.localizedDescription } }
    }
    private func respond(_ row: Record, user: Record, decision: FollowRequestDecision, source: FollowRequestDirection, generation: UUID) async {
        guard visible, acting == nil, source == direction, generation == session.generation, decision.allowed(in: source), !user.id.isEmpty,
              page.rows.contains(where: { $0.id == row.id }), !uncertainIDs.contains(row.id) else { return }
        let accountID = session.user?.id, epoch = session.generation, attempt = UUID()
        mutationID = attempt
        defer { if mutationID == attempt { acting = nil } }
        acting = row.id; requestID = UUID(); busy = false; confirmation = nil
        var succeeded = false
        do {
            _ = try await session.call(decision.endpoint, ["userId": .string(user.id)], mutation: true)
            guard visible, mutationID == attempt, direction == source, session.user?.id == accountID, session.generation == epoch else { return }
            page.handled(row.id); error = nil; succeeded = true
            await session.refreshUnread()
            await session.refreshFollowRequestBadge()
        } catch {
            if visible && mutationID == attempt && direction == source && session.user?.id == accountID && session.generation == epoch {
                uncertainIDs.insert(row.id)
                self.error = "申请处理结果待核对，请刷新后确认，不要重复提交。"
            }
        }
        if mutationID == attempt { acting = nil }
        if succeeded && visible && mutationID == attempt && direction == source && session.generation == epoch && session.user?.id == accountID && page.rows.isEmpty && page.hasMore { await load() }
    }
}
