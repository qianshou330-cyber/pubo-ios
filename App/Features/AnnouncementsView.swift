import SwiftUI
import PUBOCore

struct AnnouncementsView: View {
    @Environment(AppSession.self) private var session
    @State private var current = true
    @State private var entries: [Record] = []
    @State private var more = false
    @State private var busy = false
    @State private var error: String?
    @State private var request = UUID()
    @State private var confirm: Record?
    @State private var readIDs = Set<String>()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("公告范围", selection: $current) { Text("当前公告").tag(true); Text("历史公告").tag(false) }.pickerStyle(.segmented).accessibilityIdentifier("announcements.scope")
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 16) {
                        if entry["forYou"].bool { Label("发给你的公告", systemImage: "pin").font(.caption).foregroundStyle(.orange) }
                        NavigationLink { AnnouncementDetail(entry: entry) } label: { Label(entry["title"].string ?? "公告", systemImage: "info.circle").font(.headline).frame(minHeight: 44, alignment: .leading) }.accessibilityIdentifier("announcements.open." + entry.id)
                        NoteText(text: entry.text, remoteEmojis: .null)
                        if let url = safeMediaURL(entry["imageUrl"].string) { AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }; Link("打开公告原图", destination: url) }
                        if let date = puboDate(entry["createdAt"].string) { Text("发布时间：" + date.formatted()).font(.caption).foregroundStyle(PUBOTheme.secondary) }
                        if current && session.user != nil && entry["display"].string != "marquee" && !entry["silence"].bool && !entry["isRead"].bool && !readIDs.contains(entry.id) {
                            Button("知道了") { if entry["needConfirmationToRead"].bool { confirm = entry } else { Task { await markRead(entry) } } }.buttonStyle(.borderedProminent).disabled(busy)
                        }
                    }.puboCard()
                }
                if let error { ErrorBanner(message: error) { Task { await load(reset: entries.isEmpty) } } }
                if busy { ProgressView().frame(maxWidth: .infinity) }
                else if entries.isEmpty && error == nil { Text("暂无公告").foregroundStyle(PUBOTheme.secondary) }
                if more { Button("加载更多公告") { Task { await load(reset: false) } }.disabled(busy) }
            }.padding(16)
        }.puboScreen().navigationTitle("站内公告").navigationBarTitleDisplayMode(.inline)
            .task(id: current) { request = UUID(); entries = []; more = false; error = nil; await load(reset: true) }
            .refreshable { await load(reset: true) }
            .confirmationDialog("确认已阅读此公告？", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { item in Button("确认已阅读") { Task { await markRead(item) }; confirm = nil } }
            .onDisappear { request = UUID() }
    }
    private func load(reset: Bool) async {
        let attempt = UUID(); request = attempt; let scope = current; busy = true
        defer { if request == attempt { busy = false } }
        do {
            var fields: [String: JSONValue] = ["isActive": .bool(scope), "limit": .number(20)]
            if !reset, let last = entries.last { fields["untilId"] = .string(last.id) }
            let value = try await session.call("announcements", fields)
            try Task.checkCancellation()
            guard request == attempt, current == scope, case .array = value else { return }
            let page = Record.list(value)
            entries = Records.merge(reset ? [] : entries, page, limit: 2_000); more = page.count == 20 && entries.count < 2_000; error = nil
        } catch { if request == attempt && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func markRead(_ entry: Record) async {
        guard !busy, entry["display"].string != "marquee" else { return }; busy = true; defer { busy = false }
        do { _ = try await session.call("i/read-announcement", ["announcementId": .string(entry.id)], mutation: true); try Task.checkCancellation(); readIDs.insert(entry.id); try? await session.refreshUser() }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
