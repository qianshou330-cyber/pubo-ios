import SwiftUI
import Charts
import PUBOCore

struct ChartSongRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: JSONValue
    var playlist = false
    var compact = false
    var change: ChartRankChange?
    @State private var progress: CGFloat = 1
    @State private var highlight = false
    @State private var transitioning = false
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var artistSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var compactTitleSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var compactArtistSize: CGFloat = 10
    private var movement: ChartMovement { ChartMovement(row) }
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if transitioning, let change {
                    Text("\(change.from)").offset(y: CGFloat(change.offset) * progress).opacity(1 - progress)
                    Text("\(change.to)").offset(y: -CGFloat(change.offset) * (1 - progress)).opacity(progress)
                } else { Text("\(row["rank"].int)") }
            }.font(.system(size: titleSize, weight: .bold)).monospacedDigit().frame(minWidth: 24).accessibilityHidden(true)
            if !compact, let url = safeMediaURL(row["albumCoverUrl"].string) { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: "music.note") }.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true) }
            let artists = row["artists"].array.compactMap { $0["name"].string }.joined(separator: " / ")
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { Text(row["title"].string ?? "").font(.system(size: compactTitleSize)); Text(artists).font(.system(size: compactArtistSize)).foregroundStyle(PUBOTheme.secondary) }.lineLimit(1)
                    Text((row["title"].string ?? "") + "  " + artists).font(.system(size: compactTitleSize)).lineLimit(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row["title"].string ?? "").font(.system(size: titleSize, weight: .medium)).lineLimit(2)
                    Text(artists).font(.system(size: artistSize)).foregroundStyle(PUBOTheme.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Text(movement.label).font(.caption).foregroundStyle(chartMovementColor(movement))
        }.frame(minHeight: 44).contentShape(Rectangle()).accessibilityElement(children: .combine)
            .accessibilityLabel("\(playlist ? "歌单顺序" : "排名") \(row["rank"].int)，\(row["title"].string ?? "")，\(movement.explanation)")
            .background(PUBOTheme.accent.opacity(highlight ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
            .task(id: change) {
                transitioning = false; highlight = false; progress = 1
                guard change != nil, !reduceMotion, !ProcessInfo.processInfo.arguments.contains("--reduce-motion") else { return }
                var reset = Transaction(); reset.disablesAnimations = true
                withTransaction(reset) { transitioning = true; progress = 0 }
                do {
                    try await Task.sleep(for: .milliseconds(16))
                    withAnimation(.timingCurve(0, 0.5, 0.5, 1, duration: 0.2)) { progress = 1 }
                    withAnimation(.easeOut(duration: 0.12)) { highlight = true }
                    try await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeOut(duration: 0.48)) { highlight = false }
                    try await Task.sleep(for: .milliseconds(480))
                    transitioning = false
                } catch { transitioning = false; highlight = false; progress = 1 }
            }
    }
}

struct ChartSongSelection: Identifiable {
    let key: String
    let song: JSONValue
    var chart: JSONValue = .null
    var id: String { key + ":" + (song["songId"].string ?? "") }
}

struct ChartSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selection: ChartSongSelection
    var body: some View {
        NavigationStack {
            ChartHistoryView(chartKey: selection.key, song: selection.song, initialChart: selection.chart)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("关闭歌曲详情").accessibilityIdentifier("chart.sheet.close") } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationCornerRadius(20).presentationBackground(PUBOTheme.background)
            .accessibilityIdentifier("chart.songSheet")
    }
}

struct ChartDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var selection: ChartSongSelection?
    @State private var changes: [String: ChartRankChange] = [:]
    private var key: String { selectedKey.isEmpty ? chartKey : selectedKey }
    private var platform: String { key.hasPrefix("melon-") ? "melon" : key }
    var body: some View {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image("ChartCover").resizable().scaledToFit().frame(width: 44, height: 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) { Text("韩国女团音源榜").font(.headline); Text("韩国榜单 · 每小时更新").font(.caption) }
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选择音乐平台").font(.caption)
                        Picker("选择音乐平台", selection: Binding(get: { platform }, set: { value in let chosen = value == "melon" ? session.chartPreferences.lastMelonChart : value; selectedKey = chosen; session.selectChart(chosen) })) {
                            Text("Melon").tag("melon")
                            ForEach(Array(KpopPreferences.chartKeys.dropFirst(4)), id: \.self) { Text(chartName($0)).tag($0) }
                        }.labelsHidden().frame(maxWidth: .infinity, minHeight: 44).overlay(RoundedRectangle(cornerRadius: 10).stroke(PUBOTheme.divider)).accessibilityIdentifier("chart.filter.platform")
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选择团体").font(.caption)
                        Picker("选择团体", selection: Binding(get: { group }, set: { group = $0; session.selectChartGroup($0) })) {
                            Text("全部女团").tag("")
                            ForEach(KpopPreferences.groups, id: \.0) { Text($0.1).tag($0.0) }
                        }.labelsHidden().frame(maxWidth: .infinity, minHeight: 44).overlay(RoundedRectangle(cornerRadius: 10).stroke(PUBOTheme.divider)).accessibilityIdentifier("chart.filter.group")
                    }.frame(maxWidth: .infinity)
                }
                Text("搜索歌曲").font(.caption)
                TextField("搜索歌曲或艺人", text: $query).submitLabel(.search).padding(12).frame(minHeight: 44).overlay(RoundedRectangle(cornerRadius: 10).stroke(PUBOTheme.divider)).accessibilityIdentifier("chart.filter.query")
                if platform == "melon" {
                    Divider()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(Array(KpopPreferences.chartKeys.prefix(4)), id: \.self) { value in
                            Button { selectedKey = value; session.selectChart(value) } label: {
                                Text(chartName(value)).font(.caption.weight(key == value ? .bold : .regular)).frame(maxWidth: .infinity, minHeight: 44).background(key == value ? PUBOTheme.ownBubble : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).foregroundStyle(key == value ? PUBOTheme.accent : PUBOTheme.text).accessibilityAddTraits(key == value ? .isSelected : []).accessibilityIdentifier("chart.category." + value)
                        }
                    }
                }
            }.puboCard(padding: 16)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(chart["label"].string ?? chartName(key)).font(.headline); Spacer(); Button("刷新") { Task { await load(reset: true) } }.frame(minHeight: 44).disabled(busy).accessibilityIdentifier("chart.refresh") }
                Text(HomeContent.chartStatus(chart))
                if !HomeContent.chartScope(chart).isEmpty { Text(HomeContent.chartScope(chart)).font(.caption) }
                ChartPeriod(chart: chart)
            }.font(.caption).padding(.horizontal, 4)
            VStack(spacing: 0) {
              ForEach(entries, id: \.songIdentity) { row in
                Button { selection = ChartSongSelection(key: key, song: row, chart: chart) } label: { ChartSongRow(row: row, playlist: chart["rankBasis"].string == "playlist_order", change: changes[row.songIdentity]).padding(.vertical, 4) }.buttonStyle(.plain).accessibilityIdentifier("chart.song." + row.songIdentity)
                if row.songIdentity != entries.last?.songIdentity { Divider().overlay(PUBOTheme.divider) }
              }
            }.puboCard(padding: 12)
            if let error { ErrorBanner(message: error) { Task { await load(reset: entries.isEmpty) } } }
            if busy { ProgressView() }
            if entries.isEmpty && !busy && error == nil { Text(chart["coverage"].string == "preview" ? "当前来源预览范围未找到匹配歌曲" : "当前筛选没有匹配歌曲").foregroundStyle(.secondary) }
            if more && !entries.isEmpty { Button("加载更多") { Task { await load(reset: false) } }.disabled(busy) }
            if let url = safeMediaURL(chart["sourceUrl"].string) { Link("官方来源", destination: url) }
          }.padding(12)
        }.puboScreen().navigationTitle(chart["label"].string ?? chartName(key)).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selection) { ChartSongSheet(selection: $0) }
            .scrollDismissesKeyboard(.interactively)
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
            let previous = JSONValue.object(["chart": chart, "entries": .array(entries)])
            changes = reset && !reduceMotion ? ChartRefresh.changes(previous: previous, incoming: value) : [:]
            var seen = Set<String>()
            let updated = ((reset ? [] : entries) + incoming).filter { seen.insert($0["songId"].string ?? "").inserted }
            withAnimation(changes.isEmpty ? nil : .easeOut(duration: 0.35)) { entries = updated }
            offset = start + value["entries"].array.count; more = value["hasMore"].bool && !value["entries"].array.isEmpty
            chart = value["chart"]; error = nil
        } catch { if attempt == id && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ChartPeriod: View {
    let chart: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let period = chart["sourcePeriod"].string ?? chart["sourceDate"].string { Text("来源期次：" + (period.contains("T") ? ChartClock.korean(period) ?? period : period)) }
            else if let updated = ChartClock.korean(chart["sourceUpdatedAt"].string) { Text("来源更新时间：" + updated) }
            else { Text("来源未提供明确期次") }
            if let observed = ChartClock.korean(chart["observedAt"].string) { Text("本站观察时间：" + observed) }
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
    private var maxRank: Int { max(2, ChartMovement.integer(chart["maxRank"]) ?? 200) }
    private var rankTicks: [Int] { Array(Set([1, maxRank] + Array(stride(from: max(1, maxRank / 5), through: maxRank, by: max(1, maxRank / 5))))).sorted() }
    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(song["title"].string ?? "歌曲详情").font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                Text(song["artists"].array.compactMap { $0["name"].string }.joined(separator: " / ")).font(.subheadline).foregroundStyle(PUBOTheme.secondary)
                HStack(spacing: 8) {
                    statistic(playlist ? "歌单位置" : "当前排名", song["rank"].isNull ? "—" : String(song["rank"].int))
                    statistic("涨跌", ChartMovement(song).label, color: chartMovementColor(ChartMovement(song)))
                    statistic("7 天最佳", song["bestRank7d"].isNull ? "—" : String(song["bestRank7d"].int))
                }
                Text("变化依据：" + ChartMovement(song).basis).font(.caption).foregroundStyle(.secondary)
                if !HomeContent.chartScope(chart).isEmpty { Text(HomeContent.chartScope(chart)).font(.caption).foregroundStyle(.secondary) }
                ChartPeriod(chart: chart)
                if let metadataError { ErrorBanner(message: metadataError) { Task { await loadMetadata() } } }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(data["basis"].string == "official_period" ? "7 天走势 · 官方期次" : "7 天走势 · 本站观察").font(.subheadline.bold())
                if points.contains(where: { $0.rank != nil }) {
                    Chart(points) { point in
                        if let rank = point.rank {
                            LineMark(x: .value("日期", point.date), y: .value(playlist ? "歌单位置" : "排名", rank), series: .value("连续区段", point.segment)).lineStyle(StrokeStyle(lineWidth: 2)).foregroundStyle(PUBOTheme.accent)
                            PointMark(x: .value("日期", point.date), y: .value("位置", rank)).symbolSize(16).foregroundStyle(PUBOTheme.accent)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true, dataType: Int.self) { domain in domain = [1, maxRank] })
                    .chartYAxis { AxisMarks(position: .leading, values: rankTicks) { value in AxisGridLine(); AxisValueLabel { if let rank = value.as(Int.self) { Text("\(rank)") } } } }
                    .chartXScale(domain: .automatic(dataType: Date.self) { domain in
                        if let from = data["from"].string.flatMap(SocialContent.date), let to = data["to"].string.flatMap(SocialContent.date), from < to { domain = [from, to] }
                    })
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in AxisValueLabel { if let date = value.as(Date.self) { Text(String(ChartClock.korean(date).dropFirst(5).prefix(5))) } } } }
                    .chartLegend(.hidden).frame(height: 240)
                    .accessibilityLabel("7 天排名走势，名次范围 1 至 \(maxRank)，下方提供逐条记录")
                    .accessibilityIdentifier("chart.history.plot")
                }
                Text(data["basis"].string == "official_period" ? "按来源榜期显示；日榜日期用于定位，不代表实际公布时刻。空白不补排名，预览未检出不等于全榜未上榜。" : "按本站观察时间显示；空白不补排名，预览未检出不等于全榜未上榜。")
                    .font(.caption).foregroundStyle(PUBOTheme.secondary).accessibilityIdentifier("chart.history.basis")
                DisclosureGroup("查看排名记录（\(points.count)）") {
                ForEach(points) { point in
                    VStack(alignment: .leading, spacing: 4) {
                        if data["basis"].string == "official_period" {
                            Text("官方榜期：" + ((point.value["sourcePeriod"].string?.count == 10 ? point.value["sourcePeriod"].string : nil) ?? ChartClock.korean(point.date))).font(.caption)
                            if let observed = ChartClock.korean(point.value["observedAt"].string) { Text("本站观察时间：" + observed).font(.caption2).foregroundStyle(PUBOTheme.secondary) }
                        } else { Text("本站观察时间：" + ChartClock.korean(point.date)).font(.caption) }
                        Text(point.rank.map { "\(playlist ? "歌单位置" : "排名") \($0)" } ?? (point.value["result"].string == "not_listed" ? "本次来源范围未收录" : "暂无可靠数据"))
                        if point.value["gapBefore"].bool { Text("此前存在采集间隔").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                }.font(.caption).accessibilityIdentifier("chart.history.records")
                if busy { ProgressView() }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                else if points.isEmpty && !busy { Text("暂无历史记录") }
            }
            if let url = safeMediaURL(chart["sourceUrl"].string) { Link("官方来源", destination: url) }
            NavigationLink("查看完整榜单") { ChartDetailView(chartKey: chartKey) }
          }.padding(16)
        }.background(PUBOTheme.panel).puboScreen().navigationTitle("歌曲记录").navigationBarTitleDisplayMode(.inline)
            .task {
                chart = initialChart
                async let history: Void = load()
                if initialChart.isNull { await loadMetadata() }
                await history
            }
    }
    private func statistic(_ title: String, _ value: String, color: Color = PUBOTheme.text) -> some View {
        VStack(spacing: 6) { Text(title).font(.caption).foregroundStyle(PUBOTheme.secondary); Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(color) }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 10))
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

extension JSONValue {
    var songIdentity: String { self["songId"].string ?? "" }
}

func chartName(_ key: String) -> String {
    ["melon-top100": "Melon TOP100", "melon-hot100": "Melon HOT100", "melon-hot100-d30": "Melon HOT100 · 30天", "melon-daily": "Melon 日榜", "genie-realtime": "Genie 实时榜", "bugs-realtime": "Bugs 实时榜", "flo": "FLO", "apple": "Apple Music", "spotify": "Spotify", "tencent": "腾讯音乐", "billboard-korea-global-k-songs": "Billboard 韩国全球歌曲榜"][key] ?? key
}

/// Match the H5 chart convention: upward red, downward green.
private func chartMovementColor(_ movement: ChartMovement) -> Color {
    movement.direction > 0 ? .red : movement.direction < 0 ? .green : PUBOTheme.secondary
}
