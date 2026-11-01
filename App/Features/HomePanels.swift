import SwiftUI
import PUBOCore

private struct HomeSnapshot: Codable {
    let savedAt: Date
    let value: JSONValue
}

struct HomeAnnouncements: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [Record] = []
    @State private var error: String?
    @State private var cached = false
    @State private var loading = false
    var refreshID: Int
    private var active: Bool { session.selectedTab == 0 && scenePhase == .active }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("站内公告", systemImage: "megaphone.fill").font(.caption.bold()).foregroundStyle(PUBOTheme.accent)
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        ForEach(entries) { entry in
                            NavigationLink { AnnouncementDetail(entry: entry) } label: {
                                Text(entry["title"].string ?? "公告").font(.subheadline).lineLimit(1).frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("home.announcement." + entry.id)
                        }
                        if entries.isEmpty { Text(loading ? "加载中" : "暂无公告").font(.caption).foregroundStyle(PUBOTheme.secondary) }
                    }
                }.scrollIndicators(.hidden)
                if error != nil { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("重试公告") }
            }
            if cached || error != nil { Text(error == nil ? "公告缓存" : "公告刷新失败" ).font(.caption2).foregroundStyle(PUBOTheme.secondary) }
        }.padding(.horizontal, 10).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 12)).puboListRow()
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
            entries = HomeContent.publicAnnouncements(all); error = nil; cached = false
            if let owner = session.user?.id { try? session.store?.save(HomeSnapshot(savedAt: Date(), value: .array(entries.map(\.raw))), account: owner, key: "home-announcements") }
        } catch is CancellationError { } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct AnnouncementDetail: View {
    let entry: Record
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry["title"].string ?? "站内公告").font(.title2.bold())
                if let date = puboDate(entry["createdAt"].string) { Text(date, style: .date).font(.caption).foregroundStyle(PUBOTheme.secondary) }
                NoteText(text: entry.text, remoteEmojis: .null)
                Link("在本站查看公告", destination: Endpoint.origin.appendingPathComponent("announcements/" + entry.id))
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }.puboScreen().navigationTitle("站内公告")
    }
}

struct HomeChartPanel: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var key = "melon-top100"
    @State private var data: JSONValue = .null
    @State private var cached = false
    @State private var error: String?
    @State private var loading = false
    @State private var attempt = UUID()
    var refreshID: Int
    private var chart: JSONValue { data["selected"] }
    private var rows: [JSONValue] { HomeContent.chartRows(data, limit: 2) }
    private var active: Bool { session.selectedTab == 0 && scenePhase == .active }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image("ChartCover").resizable().scaledToFit().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("韩国女团音源榜").font(.subheadline.bold())
                    Text(chart["label"].string ?? "Melon TOP100").font(.caption2).foregroundStyle(PUBOTheme.secondary)
                }
                Spacer(minLength: 0)
                NavigationLink { ChartDetailView(chartKey: key) } label: { Text("详情").font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(PUBOTheme.accent).accessibilityIdentifier("home.chartDetail")
            }
            ForEach(rows, id: \.self) { row in
                NavigationLink { ChartHistoryView(chartKey: key, song: row) } label: { ChartSongRow(row: row, playlist: chart["rankBasis"].string == "playlist_order") }.buttonStyle(.plain)
            }
            if rows.isEmpty { Text(loading ? "加载榜单中" : "当前范围暂无可展示歌曲").font(.caption).foregroundStyle(PUBOTheme.secondary).frame(minHeight: 44) }
            HStack(alignment: .center) {
                Menu {
                    ForEach(data["charts"].array, id: \.self) { option in
                        if let value = option["chartKey"].string { Button(option["label"].string ?? value) { key = value } }
                    }
                } label: { Label(chart["provider"].string?.capitalized ?? "Melon", systemImage: "chevron.down").font(.caption).frame(minHeight: 44).padding(.horizontal, 10).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 10)) }
                .accessibilityLabel("切换榜单").disabled(data["charts"].array.isEmpty)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cached ? "本机缓存" : error != nil ? "刷新失败 · 上次数据" : HomeContent.chartStatus(chart))
                    if let date = puboDate(chart["lastSuccessAt"].string) { Text("最近成功 \(date.formatted(date: .numeric, time: .shortened))") }
                    let scope = HomeContent.chartScope(chart)
                    if !scope.isEmpty { Text(scope) }
                }.font(.caption2).foregroundStyle(PUBOTheme.secondary)
                if error != nil { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("重试榜单") }
            }
        }.puboCard(padding: 12).puboListRow()
            .task(id: "\(active)-\(key)-\(refreshID)") {
                guard active else { return }
                data = .null; cached = false
                if let owner = session.user?.id, let snapshot = try? session.store?.read(HomeSnapshot.self, account: owner, key: "chart-" + key), Date().timeIntervalSince(snapshot.savedAt) < 86_400 { data = snapshot.value; cached = true }
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
            data = value; cached = false; error = nil
            if let owner = session.user?.id { try? session.store?.save(HomeSnapshot(savedAt: Date(), value: value), account: owner, key: "chart-" + selected) }
        } catch is CancellationError { } catch { if attempt == id && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct ChartSongRow: View {
    let row: JSONValue
    var playlist = false
    private var movement: String {
        let change = row["sourceMovement"]
        switch change["type"].string {
        case "up": return "↑\(change["amount"].int)"
        case "down": return "↓\(change["amount"].int)"
        case "new": return "NEW"
        case "same": return "="
        default: return "—"
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            Text("\(row["rank"].int)").font(.subheadline.bold()).monospacedDigit().frame(minWidth: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(row["title"].string ?? "").font(.subheadline).lineLimit(2)
                Text(row["artists"].array.compactMap { $0["name"].string }.joined(separator: " / ")).font(.caption2).foregroundStyle(PUBOTheme.secondary)
            }
            Spacer(minLength: 4)
            Text(movement).font(.caption).foregroundStyle(PUBOTheme.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle()).accessibilityElement(children: .combine)
            .accessibilityLabel("\(playlist ? "歌单顺序" : "排名") \(row["rank"].int)，\(row["title"].string ?? "")，\(movement)")
    }
}

struct ChartDetailView: View {
    @Environment(AppSession.self) private var session
    let chartKey: String
    @State private var chart: JSONValue = .null
    @State private var entries: [JSONValue] = []
    @State private var offset = 0
    @State private var more = true
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text(HomeContent.chartStatus(chart))
                if !HomeContent.chartScope(chart).isEmpty { Text(HomeContent.chartScope(chart)).font(.caption) }
                if let period = chart["sourceDate"].string ?? chart["sourcePeriod"].string { Text("来源期次：" + period).font(.caption) }
                else if let date = puboDate(chart["observedAt"].string) { Text("采集时间：\(date.formatted())").font(.caption) }
            }
            ForEach(entries, id: \.self) { row in
                NavigationLink { ChartHistoryView(chartKey: chartKey, song: row) } label: { ChartSongRow(row: row, playlist: chart["rankBasis"].string == "playlist_order") }.accessibilityIdentifier("chart.song." + (row["songId"].string ?? ""))
            }
            if let error { ErrorBanner(message: error) { Task { await load(reset: false) } } }
            if more { Button(busy ? "加载中" : "加载更多") { Task { await load(reset: false) } }.disabled(busy) }
        }.puboList().navigationTitle(chart["label"].string ?? "韩国女团音源榜")
            .task { await load(reset: true) }.refreshable { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let start = reset ? 0 : offset
            let value = try await session.call("music-charts/kpop-chart", ["chartKey": .string(chartKey), "offset": .number(Double(start)), "limit": .number(50)])
            guard value["chart"]["chartKey"].string == chartKey else { throw APIError.invalidResponse }
            let incoming = HomeContent.chartRows(value)
            var seen = Set<String>(); let combined = (reset ? [] : entries) + incoming
            entries = combined.filter { seen.insert($0["songId"].string ?? "").inserted }
            offset = start + value["entries"].array.count; more = value["hasMore"].bool && !value["entries"].array.isEmpty
            chart = value["chart"]; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct ChartHistoryView: View {
    @Environment(AppSession.self) private var session
    let chartKey: String
    let song: JSONValue
    @State private var data: JSONValue = .null
    @State private var error: String?
    var body: some View {
        List {
            Text(song["artists"].array.compactMap { $0["name"].string }.joined(separator: " / "))
            Text(data["basis"].string == "official_period" ? "按来源官方期次记录" : "按本站采集时间记录").font(.caption).foregroundStyle(PUBOTheme.secondary)
            ForEach(Array(data["points"].array.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 4) {
                    if let date = puboDate(point["observedAt"].string) { Text(date.formatted()).font(.caption) }
                    Text(point["result"].string == "ranked" ? "排名 \(point["rank"].int)" : point["result"].string == "not_listed" ? "本次来源范围未收录" : "暂无可靠数据")
                    if point["gapBefore"].bool { Text("此前存在采集间隔").font(.caption2).foregroundStyle(PUBOTheme.secondary) }
                }
            }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            else if data["points"].array.isEmpty { Text(data.isNull ? "加载中" : "暂无历史记录") }
        }.puboList().navigationTitle(song["title"].string ?? "歌曲历史").task { await load() }
    }
    private func load() async {
        do { data = try await session.call("music-charts/kpop-history", ["chartKey": .string(chartKey), "songId": song["songId"]]); error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
