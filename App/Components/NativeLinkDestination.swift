import SwiftUI
import PUBOCore

struct NativeLinkTarget: Identifiable { let id = UUID(); let link: NativeLink }
struct NativeLinkDestination: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let target: NativeLink
    @State private var userID: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                switch target {
                case .note(let id): NoteDetailView(noteID: id)
                case .user(let id): ProfileView(userID: id)
                case .tag(let tag): TagTimelineView(tag: tag)
                case .handle:
                    if let userID { ProfileView(userID: userID) }
                    else if let error { ErrorBanner(message: error) { Task { await resolve() } } }
                    else { ProgressView("读取用户…") }
                }
            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .task { await resolve() }
        }
    }
    private func resolve() async {
        guard case .handle(let username, let host) = target else { return }
        do {
            var fields: [String: JSONValue] = ["username": .string(username)]
            if let host { fields["host"] = .string(host) }
            let user = Record(try await session.call("users/show", fields)); try Task.checkCancellation()
            guard !user.id.isEmpty else { throw APIError.invalidResponse }; userID = user.id; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct TagTimelineView: View {
    @Environment(AppSession.self) private var session
    let tag: String
    @State private var notes: [Record] = []
    @State private var error: String?
    @State private var busy = false
    @State private var more = true
    var body: some View {
        List {
            ForEach(notes) { NoteCard(note: $0) }
            if let error { ErrorBanner(message: error) }
            if more { Button("加载更多") { Task { await load() } }.disabled(busy) }
        }.puboList().navigationTitle("#" + tag).task { await load() }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["tag": .string(tag), "limit": .number(30)]
            if let id = notes.last?.id { fields["untilId"] = .string(id) }
            let page = Record.list(try await session.call("notes/search-by-tag", fields)); try Task.checkCancellation()
            notes = Records.merge(notes, page, limit: 5_000); more = page.count == 30; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
