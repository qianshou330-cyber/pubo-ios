import SwiftUI
import PUBOCore

/// Secondary destinations retained from the former home page.
struct WorldDiscoveryView: View {
    @Environment(AppSession.self) private var session
    @State private var refresh = 0
    @State private var destination: HomeDestination?
    @State private var songSelection: ChartSongSelection?

    var body: some View {
        List {
            Section("站内公告") {
                HomeAnnouncements(refreshID: refresh) { destination = $0 }
                NavigationLink("全部公告") { AnnouncementsView() }
            }
            Section("榜单") {
                HomeChartPanel(refreshID: refresh) { target in
                    if case .history(let key, let song, let chart) = target {
                        songSelection = ChartSongSelection(key: key, song: song, chart: chart)
                    } else { destination = target }
                }
            }
            Section("社区") {
                NavigationLink("通知") { NotificationsView() }.accessibilityIdentifier("world.notifications")
                ForEach(CollectionKind.allCases) { kind in
                    NavigationLink(kind.title) { CollectionsView(kind: kind) }
                }
                NavigationLink("探索热门") { FeaturedNotesView() }
                NavigationLink("搜索") { SearchView() }
            }
            Section {
                Text("推荐展示本站现有公开时间线，不使用附近定位，也不是个性化推荐算法。")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("更多功能") { MoreSocialView() }
            }
        }.puboList().navigationTitle("发现").toolbar(.visible, for: .navigationBar)
            .navigationDestination(item: $destination) { $0.view }
            .sheet(item: $songSelection) { ChartSongSheet(selection: $0) }
            .refreshable { refresh += 1 }
    }
}
