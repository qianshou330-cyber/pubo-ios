import SwiftUI
import PUBOCore

struct GuestFeed: View {
    @Environment(AppSession.self) private var session
    @State private var notes: [Record] = []
    @State private var error: String?
    @State private var busy = false
    @State private var more = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("公开动态").font(.headline)
            ForEach(notes) { NoteCard(note: $0) }
            if let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }
            if busy { ProgressView() }
            if more { Button("加载更多公开动态") { Task { await load() } }.disabled(busy) }
        }.task { await load(reset: true) }
    }
    private func load(reset: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["limit": .number(20)]
            if !reset, let id = notes.last?.id { fields["untilId"] = .string(id) }
            // Public endpoint and visibility are both enforced. No guest home-timeline call.
            let value = try await session.call("notes/local-timeline", fields)
            try Task.checkCancellation(); guard case .array = value else { throw APIError.invalidResponse }
            let page = Record.list(value).filter { $0["visibility"].string == "public" }
            notes = Records.merge(reset ? [] : notes, page, limit: 2_000); more = value.array.count == 20; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
