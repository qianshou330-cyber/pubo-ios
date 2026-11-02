import SwiftUI
import Charts
import PUBOCore

struct ChartSongRow: View {
    let row: JSONValue
    var playlist = false
    private var movement: ChartMovement { ChartMovement(row) }
    var body: some View {
        HStack(spacing: 8) {
            Text("\(row["rank"].int)").font(.subheadline.bold()).monospacedDigit().frame(minWidth: 24)
            if let url = safeMediaURL(row["albumCoverUrl"].string) { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: "music.note") }.frame(width: 40, height: 40).clipped().accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 2) {
                Text(row["title"].string ?? "").font(.subheadline).lineLimit(2)
                Text(row["artists"].array.compactMap { $0["name"].string }.joined(separator: " / ")).font(.caption2).foregroundStyle(PUBOTheme.secondary)
            }
            Spacer(minLength: 4)
            Text(movement.label).font(.caption).foregroundStyle(movement.direction > 0 ? .green : movement.direction < 0 ? .red : PUBOTheme.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle()).accessibilityElement(children: .combine)
            .accessibilityLabel("\(playlist ? "歌单顺序" : "排名") \(row["rank"].int)，\(row["title"].string ?? "")，\(movement.explanation)")
    }
}

struct ChartDetailView: View {
    @Environment(AppSession.self) private var session
    let chartKey: String
    @State private var selectedKey = ""
    @State private var group = ""
    @State private var query = ""
    @State private var chart: JSONValue = .null
    @State private var entries: [JSONValue] = []
    @State private var offset = 0
    @State private var more = true
    @State private var busy = false
    @State private var error: String?
    @State private var attempt = UUID()
    @State private var loadedContext = ""
    private var key: String { selectedKey.isEmpty ? chartKey : selectedKey }
    var body: some View {
        List {
            Section("筛选") {
                Picker("榜单", selection: Binding(get: { key }, set: { selectedKey = $0; session.selectChart($0) })) {
                    ForEach(KpopPreferences.chartKeys, id: \.self) { Text(chartName($0)).tag($0) }
                }.accessibilityIdentifier("chart.filter.platform")
                Picker("女团", selection: Binding(get: { group }, set: { group = $0; session.selectChartGroup($0) })) {
                    Text("全部女团").tag("")
                    ForEach(KpopPreferences.groups, id: \.0) { Text($0.1).tag($0.0) }
                }.accessibilityIdentifier("chart.filter.group")
                TextField("搜索歌曲或艺人", text: $query).submitLabel(.search).accessibilityIdentifier("chart.filter.query")
            }
            Section {
                Text(HomeContent.chartStatus(chart))
                if !HomeContent.chartScope(chart).isEmpty { Text(HomeContent.chartScope(chart)).font(.caption) }
                ChartPeriod(chart: chart)
            }
            ForEach(entries, id: \.self) { row in
                NavigationLink { ChartHistoryView(chartKey: key, song: row, initialChart: chart) } label: { ChartSongRow(row: row, playlist: chart["rankBasis"].string == "playlist_order") }.accessibilityIdentifier("chart.song." + (row["songId"].string ?? ""))
            }
            if let error { ErrorBanner(message: error) { Task { await load(reset: entries.isEmpty) } } }
            if busy { ProgressView() }
            if entries.isEmpty && !busy && error == nil { Text(chart["coverage"].string == "preview" ? "当前来源预览范围未找到匹配歌曲" : "当前筛选没有匹配歌曲").foregroundStyle(.secondary) }
            if more && !entries.isEmpty { Button("加载更多") { Task { await load(reset: false) } }.disabled(busy) }
            if let url = safeMediaURL(chart["sourceUrl"].string) { Link("官方来源", destination: url) }
        }.puboList().navigationTitle(chart["label"].string ?? chartName(key))
            .task { group = session.chartPreferences.groupID }
            .task(id: "\(key)|\(group)|\(query)") {
                attempt = UUID(); busy = false
                let context = "\(key)|\(group)|\(query)"
                if loadedContext != context { entries = []; chart = .null; error = nil; offset = 0; more = true; loadedContext = context }
                do { if !query.isEmpty { try await Task.sleep(for: .milliseconds(350)) }; try Task.checkCancellation(); await load(reset: true) } catch { }
            }.refreshable { await load(reset: true) }
            .onDisappear { attempt = UUID(); busy = false }
    }
    private func load(reset: Bool) async {
        guard !busy else { return }; busy = true; let id = UUID(); attempt = id
        defer { if attempt == id { busy = false } }
        do {
            let start = reset ? 0 : offset; let requestedKey = key
            var fields: [String: JSONValue] = ["chartKey": .string(requestedKey), "offset": .number(Double(start)), "limit": .number(50), "query": .string(String(query.prefix(200)))]
            if !group.isEmpty { fields["groupId"] = .string(group) }
            let value = try await session.call("music-charts/kpop-chart", fields)
            guard attempt == id, !Task.isCancelled else { return }
            guard value["chart"]["chartKey"].string == requestedKey else { throw APIError.invalidResponse }
            let incoming = HomeContent.chartRows(value)
            var seen = Set<String>(); entries = ((reset ? [] : entries) + incoming).filter { seen.insert($0["songId"].string ?? "").inserted }
            offset = start + value["entries"].array.count; more = value["hasMore"].bool && !value["entries"].array.isEmpty
            chart = value["chart"]; error = nil
        } catch { if attempt == id && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ChartPeriod: View {
    let chart: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let period = chart["sourceDate"].string ?? chart["sourcePeriod"].string { Text("来源期次：" + period) }
            else if let updated = puboDate(chart["sourceUpdatedAt"].string) { Text("来源更新时间：" + updated.formatted()) }
            else { Text("来源未提供明确期次") }
            if let observed = puboDate(chart["observedAt"].string) { Text("本站观察时间：" + observed.formatted()) }
            if chart["status"].string != "available", !chart["observedAt"].isNull { Text("当前展示上次取得的数据") }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct ChartHistoryView: View {
    @Environment(AppSession.self) private var session
    let chartKey: String
    let song: JSONValue
    var initialChart: JSONValue = .null
    @State private var data: JSONValue = .null
    @State private var chart: JSONValue = .null
    @State private var error: String?
    @State private var metadataError: String?
    @State private var busy = false
    private var points: [ChartHistoryPoint] { ChartHistoryPoint.parse(data) }
    private var playlist: Bool { chart["rankBasis"].string == "playlist_order" }
    var body: some View {
        List {
            Section {
                Text(song["artists"].array.compactMap { $0["name"].string }.joined(separator: " / "))
                LabeledContent(playlist ? "歌单位置" : "当前排名", value: song["rank"].isNull ? "—" : String(song["rank"].int))
                LabeledContent("涨跌", value: ChartMovement(song).label)
                LabeledContent("7 天最佳", value: song["bestRank7d"].isNull ? "—" : String(song["bestRank7d"].int))
                Text("变化依据：" + ChartMovement(song).basis).font(.caption).foregroundStyle(.secondary)
                ChartPeriod(chart: chart)
                if let metadataError { ErrorBanner(message: metadataError) { Task { await loadMetadata() } } }
            }
            Section(data["basis"].string == "official_period" ? "7 天走势 · 官方期次" : "7 天走势 · 本站观察") {
                if points.contains(where: { $0.rank != nil }) {
                    Chart(points) { point in
                        if let rank = point.rank {
                            LineMark(x: .value("日期", point.date), y: .value(playlist ? "歌单位置" : "排名", rank), series: .value("连续区段", point.segment)).foregroundStyle(PUBOTheme.accent)
                            PointMark(x: .value("日期", point.date), y: .value("位置", rank)).foregroundStyle(PUBOTheme.accent)
                        }
                    }.chartYScale(domain: .automatic(includesZero: false, reversed: true)).frame(height: 200).accessibilityLabel("7 天排名走势，下方提供逐条记录")
                }
                ForEach(points) { point in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(point.date.formatted()).font(.caption)
                        Text(point.rank.map { "\(playlist ? "歌单位置" : "排名") \($0)" } ?? (point.value["result"].string == "not_listed" ? "本次来源范围未收录" : "暂无可靠数据"))
                        if point.value["gapBefore"].bool { Text("此前存在采集间隔").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                if busy { ProgressView() }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                else if points.isEmpty && !busy { Text("暂无历史记录") }
            }
            if let url = safeMediaURL(chart["sourceUrl"].string) { Link("官方来源", destination: url) }
            NavigationLink("查看完整榜单") { ChartDetailView(chartKey: chartKey) }
        }.puboList().navigationTitle(song["title"].string ?? "歌曲历史")
            .task { chart = initialChart; await load() }
            .task { if initialChart.isNull { await loadMetadata() } }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let value = try await session.call("music-charts/kpop-history", ["chartKey": .string(chartKey), "songId": song["songId"]]); try Task.checkCancellation(); data = value; error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadMetadata() async {
        do { let value = try await session.call("music-charts/kpop-summary", ["chartKey": .string(chartKey)]); try Task.checkCancellation(); chart = value["selected"]; metadataError = nil }
        catch { if !Task.isCancelled { metadataError = "榜单来源信息加载失败" } }
    }
}

func chartName(_ key: String) -> String {
    ["melon-top100": "Melon TOP100", "melon-hot100": "Melon HOT100", "melon-hot100-d30": "Melon HOT100 · 30天", "melon-daily": "Melon 日榜", "genie-realtime": "Genie 实时榜", "bugs-realtime": "Bugs 实时榜", "flo": "FLO", "apple": "Apple Music", "spotify": "Spotify", "tencent": "腾讯音乐", "billboard-korea-global-k-songs": "Billboard 韩国全球歌曲榜"][key] ?? key
}
