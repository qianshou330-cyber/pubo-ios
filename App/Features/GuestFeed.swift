import SwiftUI
import PUBOCore

struct GuestFeed: View {
    @Environment(AppSession.self) private var session
    @State private var feed = TimelineState()
    @State private var error: String?
    @State private var busy = false
    @State private var more = true
    @State private var requestID = UUID()
    private var preferences: TimelinePreferences { session.timelinePreferences }
    private var context: String { session.generation.uuidString + preferences.requestKey }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("公开动态").font(.headline); Spacer()
                Menu("筛选") {
                    Toggle("显示转帖", isOn: Binding(get: { preferences.withRenotes }, set: { session.timelinePreferences.withRenotes = $0 }))
                    Toggle("在时间线中显示对他人的回复", isOn: Binding(get: { preferences.withReplies }, set: { session.timelinePreferences.setReplies($0) }))
                    Toggle("显示包含敏感媒体的帖子", isOn: Binding(get: { preferences.withSensitive }, set: { session.timelinePreferences.withSensitive = $0 }))
                    Toggle("仅限媒体", isOn: Binding(get: { preferences.onlyFiles }, set: { session.timelinePreferences.setOnlyFiles($0) }))
                }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("guest.timeline.filters")
            }
            ForEach(Array(feed.notes.enumerated()), id: \.element.id) { index, note in
                NoteCard(note: note, hideSensitive: !preferences.withSensitive, appearance: .timeline)
                    .onAppear { if index >= feed.notes.count - 5 && more && error == nil { Task { await load() } } }
            }
            if let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }
            if busy { ProgressView() }
        }.task(id: context) { requestID = UUID(); busy = false; feed.reset(); more = true; error = nil; await load(reset: true) }
            .onDisappear { requestID = UUID() }
            .onChange(of: preferences) { _, _ in session.saveTimelinePreferences() }
    }
    private func load(reset: Bool = false) async {
        guard !busy, reset || more else { return }
        let attempt = UUID(), requested = context, selected = preferences
        requestID = attempt; busy = true; defer { if requestID == attempt { busy = false } }
        do {
            var fields = selected.parameters; fields["limit"] = .number(20)
            if !reset, let id = feed.olderCursor { fields["untilId"] = .string(id) }
            // Public endpoint and visibility are both enforced. No guest home-timeline call.
            let value = try await session.call("notes/local-timeline", fields)
            try Task.checkCancellation(); guard requestID == attempt, requested == context else { return }; guard case .array = value else { throw APIError.invalidResponse }
            let page = Record.list(value).filter { $0["visibility"].string == "public" }
            feed.page(page, older: !reset, preferences: selected, accountID: nil); more = value.array.count == 20; error = nil
        } catch { if !Task.isCancelled, requestID == attempt, context == requested { self.error = error.localizedDescription } }
    }
}
