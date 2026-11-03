import SwiftUI
import PUBOCore

struct AnnouncementEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let original: Record
    var onSaved: () -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var imageURL = ""
    @State private var busy = false
    @State private var conflict = false
    @State private var error: String?
    @State private var baseline: Record?
    var body: some View {
        Group {
            AdminGate {
                Form {
                    TextField("公告标题", text: $title).accessibilityIdentifier("announcement.title")
                    TextEditor(text: $text).frame(minHeight: 180).accessibilityLabel("公告正文")
                    TextField("图片 HTTPS 地址（可选）", text: $imageURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    if let error { ErrorBanner(message: error) }
                    if conflict { Button("重新读取最新版本") { Task { await reload() } } }
                    Button("保存修改") { Task { await save() } }.disabled(busy || conflict || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.puboForm().navigationTitle("修改公告").disabled(busy)
                    .task { if baseline == nil { select(original) } }
            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
        }.toolbar(.visible, for: .navigationBar).interactiveDismissDisabled(busy)
    }
    private func select(_ value: Record) { baseline = value; title = value["title"].string ?? ""; text = value.text; imageURL = value["imageUrl"].string ?? ""; conflict = false; error = nil }
    private func latest() async throws -> Record {
        var cursor: String?; var seen = Set<String>()
        repeat {
            var fields: [String: JSONValue] = ["display": .string("marquee"), "isActive": .bool(true), "limit": .number(100)]
            if let cursor { fields["untilId"] = .string(cursor) }
            let response = try await session.call("announcements", fields)
            guard case .array = response else { throw APIError.invalidResponse }
            let rows = Record.list(response)
            if let current = HomeContent.publicAnnouncements(rows).first(where: { $0.id == original.id }) { return current }
            if rows.count < 100 { break }
            guard let next = rows.last?.id, seen.insert(next).inserted else { throw APIError.invalidResponse }; cursor = next
        } while !Task.isCancelled
        try Task.checkCancellation()
        throw APIError(code: "ANNOUNCEMENT_UNAVAILABLE", message: "公告已结束、删除或改变显示方式，不能从旧页面覆盖。")
    }
    private func reload() async { do { select(try await latest()) } catch { self.error = error.localizedDescription } }
    private func save() async {
        guard !busy, let baseline else { return }; busy = true; defer { busy = false }
        do {
            let current = try await latest()
            guard ["updatedAt", "title", "text", "imageUrl"].allSatisfy({ current[$0] == baseline[$0] }) else { conflict = true; throw APIError(code: "CONFLICT", message: "公告已被其他管理员修改，请重新读取后再编辑。") }
            let image = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard image.isEmpty || safeMediaURL(image) != nil else { throw APIError(code: "INVALID_URL", message: "图片地址必须是有效的 HTTPS 地址。") }
            let values: [String: JSONValue] = ["title": .string(title), "text": .string(text), "imageUrl": image.isEmpty ? .null : .string(image)]
            var changes = values.filter { baseline[$0.key] != $0.value }; changes["id"] = .string(original.id)
            guard changes.count > 1 else { dismiss(); return }
            do { _ = try await session.admin.call(session: session, path: "admin/announcements/update", fields: changes, mutation: true) }
            catch {
                if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error }
                let verified = try await latest()
                guard values.allSatisfy({ verified[$0.key] == $0.value }) else { conflict = true; throw APIError.uncertain }
            }
            let verified = try await latest()
            guard values.allSatisfy({ verified[$0.key] == $0.value }) else { conflict = true; throw APIError.uncertain }
            onSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

