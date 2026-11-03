import SwiftUI
import PUBOCore

private struct HomeSnapshot: Codable {
    let savedAt: Date
    let value: JSONValue
}

enum HomeDestination: Hashable {
    case announcement(JSONValue)
    case announcementEdit(JSONValue)
    case chart(String)
    case history(String, JSONValue)

    @ViewBuilder var view: some View {
        switch self {
        case .announcement(let value): AnnouncementDetail(entry: Record(value))
        case .announcementEdit(let value): AnnouncementEditor(original: Record(value)) {}
        case .chart(let key): ChartDetailView(chartKey: key)
        case .history(let key, let song): ChartHistoryView(chartKey: key, song: song)
        }
    }
}

struct HomeAnnouncements: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [Record] = []
    @State private var error: String?
    @State private var cached = false
    @State private var loading = false
    @State private var firstLoadFinished = false
    @State private var visible = false
    var refreshID: Int
    var open: (HomeDestination) -> Void
    private var active: Bool { visible && session.selectedTab == 0 && scenePhase == .active }

    var body: some View {
        Group {
        if entries.isEmpty && !firstLoadFinished && error == nil {
            AnnouncementLoadingSkeleton()
        } else if !entries.isEmpty || error != nil {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("站内公告", systemImage: "megaphone.fill").font(.caption.bold()).foregroundStyle(PUBOTheme.accent)
                RollingAnnouncementTitles(entries: entries, active: active) { open(.announcement($0.raw)) }
                if session.user?["isAdmin"].bool == true && !entries.isEmpty {
                    Menu { ForEach(entries) { entry in Button("修改：" + (entry["title"].string ?? "公告")) { open(.announcementEdit(entry.raw)) }.accessibilityIdentifier("announcement.edit." + entry.id) } } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.borderless).accessibilityLabel("修改公告")
                }
                if error != nil { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("重试公告") }
            }
            if cached || error != nil { Text(error == nil ? "公告缓存" : "公告刷新失败" ).font(.caption2).foregroundStyle(PUBOTheme.secondary) }
        }.padding(.horizontal, 10).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        }
        }.puboListRow()
            .onAppear { visible = true }.onDisappear { visible = false }
            .task(id: "\(active)-\(refreshID)") {
                guard active else { return }
                if entries.isEmpty, let owner = session.user?.id,
                   let snapshot = try? session.store?.read(HomeSnapshot.self, account: owner, key: "home-announcements"), Date().timeIntervalSince(snapshot.savedAt) < 86_400 {
                    entries = HomeContent.publicAnnouncements(Record.list(snapshot.value)); cached = !entries.isEmpty
                }
                repeat {
                    await load()
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                } while !Task.isCancelled && active
            }
    }
    private func load() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            var all: [Record] = []; var cursor: String?; var cursors = Set<String>()
            repeat {
                try Task.checkCancellation()
                var fields: [String: JSONValue] = ["display": .string("marquee"), "isActive": .bool(true), "limit": .number(100)]
                if let cursor { fields["untilId"] = .string(cursor) }
                let value = try await session.call("announcements", fields)
                guard case .array = value else { throw APIError.invalidResponse }
                let page = Record.list(value); all += page
                if page.count < 100 { break }
                guard let next = page.last?.id, cursors.insert(next).inserted else { throw APIError.invalidResponse }
                cursor = next
            } while !Task.isCancelled
            try Task.checkCancellation()
            entries = HomeContent.publicAnnouncements(all); error = nil; cached = false; firstLoadFinished = true
            if let owner = session.user?.id { try? session.store?.save(HomeSnapshot(savedAt: Date(), value: .array(entries.map(\.raw))), account: owner, key: "home-announcements") }
        } catch is CancellationError { } catch { if !Task.isCancelled { firstLoadFinished = true; self.error = error.localizedDescription } }
    }
}

struct AnnouncementDetail: View {
    @Environment(AppSession.self) private var session
    let entry: Record
    @State private var current: Record?
    @State private var error: String?
    private var shown: Record { current ?? entry }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(shown["title"].string ?? "站内公告", systemImage: "info.circle").font(.headline)
                NoteText(text: shown.text, remoteEmojis: .null)
                if let url = safeMediaURL(shown["imageUrl"].string) { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }; Link("打开公告原图", destination: url) }
                if let date = puboDate(shown["createdAt"].string) { Text("创建日期：" + date.formatted()).font(.caption).foregroundStyle(PUBOTheme.secondary) }
                if let error { ErrorBanner(message: error) }
                Link("在本站查看公告", destination: Endpoint.origin.appendingPathComponent("announcements/" + entry.id))
            }.font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).puboCard().padding(12)
        }.puboScreen().navigationTitle("站内公告").task {
            do { let value = Record(try await session.call("announcements/show", ["announcementId": .string(entry.id)])); try Task.checkCancellation(); guard value.id == entry.id else { throw APIError.invalidResponse }; current = value }
            catch { if !Task.isCancelled { self.error = "最新公告读取失败，当前显示进入页面时的内容。" } }
        }
    }
}

struct HomeChartPanel: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var key: String { session.chartPreferences.chartKey }
    @State private var data: JSONValue = .null
    @State private var cached = false
    @State private var error: String?
    @State private var loading = false
    @State private var attempt = UUID()
    @State private var changes: [String: ChartRankChange] = [:]
    @State private var visible = false
    var refreshID: Int
    var open: (HomeDestination) -> Void
    private var chart: JSONValue { data["selected"] }
    private var rows: [JSONValue] { HomeContent.chartRows(data, limit: 2) }
    private var active: Bool { visible && session.selectedTab == 0 && scenePhase == .active }
    var body: some View {
        Group {
        if data.isNull && error == nil {
            ChartLoadingSkeleton()
        } else {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image("ChartCover").resizable().scaledToFit().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("韩国女团音源榜").font(.system(size: 14, weight: .bold))
                    Text("每小时更新 · " + (chart["label"].string ?? "Melon TOP100")).font(.caption2).foregroundStyle(PUBOTheme.secondary)
                }
                Spacer(minLength: 0)
                Button { open(.chart(key)) } label: { Text("详情").font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.buttonStyle(.borderless).foregroundStyle(PUBOTheme.accent).accessibilityIdentifier("home.chartDetail")
            }
            ForEach(rows, id: \.songIdentity) { row in
                Button { open(.history(key, row)) } label: { ChartSongRow(row: row, playlist: chart["rankBasis"].string == "playlist_order", compact: true, change: changes[row.songIdentity]) }.buttonStyle(.borderless).foregroundStyle(PUBOTheme.text).accessibilityIdentifier("home.song." + row.songIdentity)
            }
            if rows.isEmpty { Text(loading ? "加载榜单中" : "当前范围暂无可展示歌曲").font(.caption).foregroundStyle(PUBOTheme.secondary).frame(minHeight: 44) }
            HStack(alignment: .center) {
                Menu {
                    ForEach(data["charts"].array, id: \.self) { option in
                        if let value = option["chartKey"].string { Button(option["label"].string ?? value) { session.selectChart(value) } }
                    }
                } label: { Label(chart["provider"].string?.capitalized ?? "Melon", systemImage: "chevron.down").font(.caption).frame(minHeight: 44).padding(.horizontal, 10).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 10)) }
                .accessibilityLabel("切换榜单").disabled(data["charts"].array.isEmpty)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cached ? "本机缓存" : error != nil ? "刷新失败 · 上次数据" : HomeContent.chartStatus(chart))
                    if let date = ChartClock.korean(chart["lastSuccessAt"].string) { Text("最近成功 " + String(date.dropFirst(5).prefix(11))).accessibilityLabel("最近成功 " + date) }
                    let scope = HomeContent.chartScope(chart)
                    if !scope.isEmpty { Text(scope) }
                }.font(.caption2).foregroundStyle(PUBOTheme.secondary)
                if error != nil { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("重试榜单") }
            }
        }.puboCard(padding: 12)
        }
        }.puboListRow()
            .onAppear { visible = true }.onDisappear { visible = false; changes = [:]; attempt = UUID() }
            .task(id: "\(active)-\(key)-\(refreshID)") {
                guard active else { return }
                if data["selected"]["chartKey"].string != key {
                    data = .null; cached = false; error = nil
                    if let owner = session.user?.id, let snapshot = try? session.store?.read(HomeSnapshot.self, account: owner, key: "chart-" + key), Date().timeIntervalSince(snapshot.savedAt) < 86_400 { data = snapshot.value; cached = true }
                }
                repeat {
                    await load()
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                } while !Task.isCancelled && active
            }
    }
    private func load() async {
        let id = UUID(); attempt = id; let selected = key; loading = true
        defer { if attempt == id { loading = false } }
        do {
            let value = try await session.call("music-charts/kpop-summary", ["chartKey": .string(selected)])
            try Task.checkCancellation()
            guard attempt == id, selected == key else { return }
            guard value["selected"]["chartKey"].string == selected else { throw APIError.invalidResponse }
            changes = !cached && !reduceMotion && active ? ChartRefresh.changes(previous: data, incoming: value) : [:]
            withAnimation(changes.isEmpty ? nil : .easeOut(duration: 0.35)) { data = value }
            cached = false; error = nil
            if let owner = session.user?.id { try? session.store?.save(HomeSnapshot(savedAt: Date(), value: value), account: owner, key: "chart-" + selected) }
        } catch is CancellationError { } catch { if attempt == id && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

