import SwiftUI

/// The shimmer is local animation, with no network requests or artificial delay.
/// VoiceOver reads one loading label; Reduce Motion and background scenes stay still.
private struct SkeletonSurface<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = false
    let label: String
    @ViewBuilder var content: () -> Content
    private var animated: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--reduce-motion") { return false }
        #endif
        return !reduceMotion && scenePhase == .active
    }

    var body: some View {
        content()
            .foregroundStyle(PUBOTheme.adaptive(0xe9ecea, 0x2a3932))
            .overlay {
                if animated {
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.7)
                            .offset(x: phase ? geometry.size.width * 1.7 : -geometry.size.width * 0.7)
                    }.mask { content() }
                }
            }
            .clipped().allowsHitTesting(false)
            .accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue(animated ? "加载中，动画占位" : "加载中，静态占位")
            .task(id: animated) {
                phase = false
                guard animated else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = true }
            }
    }
}

private struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var body: some View { RoundedRectangle(cornerRadius: 4).frame(width: width, height: height) }
}

struct PostLoadingSkeleton: View {
    var body: some View {
        SkeletonSurface(label: "正在加载帖子") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 7) { SkeletonLine(width: 100); SkeletonLine(width: 65, height: 9) }
                    Spacer()
                    SkeletonLine(width: 38, height: 9)
                }
                SkeletonLine()
                SkeletonLine()
                HStack { SkeletonLine(); Spacer().frame(width: 60) }
                HStack(spacing: 24) { ForEach(0..<3) { _ in Circle().frame(width: 18, height: 18) }; Spacer() }.padding(.top, 8)
            }
        }.puboCard(padding: 12).accessibilityIdentifier("loading.post")
    }
}

struct AnnouncementLoadingSkeleton: View {
    var body: some View {
        SkeletonSurface(label: "正在加载公告") {
            HStack(spacing: 12) { SkeletonLine(width: 55); SkeletonLine(); Spacer().frame(width: 24) }.frame(height: 44)
        }.padding(.horizontal, 10).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("loading.announcements")
    }
}

struct ChartLoadingSkeleton: View {
    var body: some View {
        SkeletonSurface(label: "正在加载榜单") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 8) { SkeletonLine(width: 128); SkeletonLine(width: 86, height: 9) }
                    Spacer()
                }
                HStack(spacing: 12) { SkeletonLine(width: 18); SkeletonLine(); Spacer().frame(width: 24) }
                HStack(spacing: 12) { SkeletonLine(width: 18); SkeletonLine(); Spacer().frame(width: 60) }
                HStack { SkeletonLine(width: 82, height: 30); Spacer(); SkeletonLine(width: 86, height: 9) }
            }
        }.puboCard(padding: 12).accessibilityIdentifier("loading.charts")
    }
}

struct AppLaunchSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PUBOBrand(width: 150).padding(.vertical, 24)
                PostLoadingSkeleton()
                PostLoadingSkeleton()
            }.padding(16).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }.scrollDisabled(true).background(PUBOTheme.background.ignoresSafeArea())
            .accessibilityElement(children: .ignore).accessibilityLabel("正在加载 PUBO")
            .accessibilityIdentifier("loading.launch")
    }
}
