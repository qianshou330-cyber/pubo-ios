import SwiftUI
import PUBOCore

private struct AnnouncementWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The first group owns accessibility; duplicate visual groups close the loop.
struct RollingAnnouncementTitles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let entries: [Record]
    let active: Bool
    let open: (Record) -> Void
    @State private var width: CGFloat = 1
    @State private var started: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var hovered = false
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 12
    private var staticMode: Bool { reduceMotion || voiceOver || ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var paused: Bool { !active || hovered || focused || staticMode }

    private func titles(copy: Bool = false) -> some View {
        HStack(spacing: 40) {
            ForEach(entries) { entry in
                if copy {
                    Text(entry["title"].string ?? "公告").font(.system(size: titleSize)).lineLimit(1).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).onTapGesture { open(entry) }
                } else {
                    Button { open(entry) } label: { Text(entry["title"].string ?? "公告").font(.system(size: titleSize)).lineLimit(1).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).focused($focused).accessibilityIdentifier("home.announcement." + entry.id)
                }
            }
        }.padding(.trailing, 40).fixedSize(horizontal: true, vertical: false).accessibilityHidden(copy)
    }
    var body: some View {
        Group {
            if staticMode {
                ScrollView(.horizontal) { titles() }.scrollIndicators(.hidden)
            } else {
                GeometryReader { geometry in
                    SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { context in
                        let seconds = elapsed + (started.map { max(0, context.date.timeIntervalSince($0)) } ?? 0)
                        let duration = max(8, Double(width) / 32)
                        let shift = CGFloat(seconds.truncatingRemainder(dividingBy: duration) / duration) * width
                        HStack(spacing: 0) {
                            titles().background(GeometryReader { measured in Color.clear.preference(key: AnnouncementWidth.self, value: measured.size.width) })
                            ForEach(0..<max(2, min(12, Int(ceil(geometry.size.width / max(1, width))) + 1)), id: \.self) { _ in titles(copy: true) }
                        }.offset(x: -shift)
                    }
                }.clipped()
            }
        }.frame(height: 44)
            .onPreferenceChange(AnnouncementWidth.self) { if $0 > 0 { width = $0 } }
            .onHover { hovered = $0 }
            .onChange(of: paused, initial: true) { _, stopped in
                if stopped { if let started { elapsed += Date().timeIntervalSince(started) }; started = nil }
                else if started == nil { started = Date() }
            }
            .onChange(of: entries) { _, _ in elapsed = 0; started = paused ? nil : Date() }
            .onDisappear { if let started { elapsed += Date().timeIntervalSince(started) }; started = nil }
    }
}
