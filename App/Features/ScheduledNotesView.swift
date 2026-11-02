import SwiftUI
import PUBOCore

struct ScheduledNotesView: View {
    @Environment(AppSession.self) private var session
    @State private var rows: [Record] = []
    @State private var error: String?
    @State private var busy = false
    @State private var more = true
    @State private var selected: Record?
    var body: some View {
        List {
            Text("服务器保存的定时帖子；仅列出当前账号。").font(.caption)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    if case .number(let milliseconds) = row["scheduledAt"] { Text(Date(timeIntervalSince1970: milliseconds / 1000).formatted()).font(.headline) }
                    NoteText(text: row["cw"].string ?? row.text)
                    Text("\(row["files"].array.count) 个附件").font(.caption)
                    Button("取消定时，保留服务器草稿", role: .destructive) { selected = row }.disabled(busy)
                }
            }
            if let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }
            if more { Button("加载更多") { Task { await load() } }.disabled(busy) }
            if !busy && rows.isEmpty && error == nil { Text("暂无定时帖子") }
        }.puboList().navigationTitle("定时帖子").task { await load(reset: true) }.refreshable { await load(reset: true) }
            .confirmationDialog("取消此帖的自动发布？正文和附件仍保留为服务器草稿。", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                if let row = selected { Button("取消定时发布", role: .destructive) { Task { await cancel(row) } } }
            }
    }
    private func load(reset: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["limit": .number(30), "scheduled": .bool(true)]
            if !reset, let id = rows.last?.id { fields["untilId"] = .string(id) }
            let value = try await session.call("notes/drafts/list", fields); try Task.checkCancellation()
            guard case .array = value else { throw APIError.invalidResponse }
            rows = Records.merge(reset ? [] : rows, Record.list(value), limit: 5_000); more = value.array.count == 30; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func cancel(_ row: Record) async {
        guard !busy else { return }; busy = true; defer { busy = false; selected = nil }
        do {
            let response = try await session.call("notes/drafts/update", ["draftId": .string(row.id), "scheduledAt": .null, "isActuallyScheduled": .bool(false)], mutation: true)
            guard !response["updatedDraft"]["isActuallyScheduled"].bool, response["updatedDraft"]["id"].string == row.id else { throw APIError.uncertain }
            rows.removeAll { $0.id == row.id }; error = nil
        } catch { self.error = "操作结果需核对，请刷新定时列表后检查。" }
    }
}
