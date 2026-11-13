import SwiftUI
import PUBOCore

struct ChatTab: Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct ChatTabs: View {
    @ScaledMetric(relativeTo: .caption) private var labelSize = 12.6
    @Binding var selection: String
    let items: [ChatTab]
    var prefix = "chat.tab."
    private var tabItems: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button { selection = item.id } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 4) { Image(systemName: item.icon); Text(item.title) }
                            .font(.system(size: labelSize, weight: selection == item.id ? .semibold : .regular))
                            .fixedSize().frame(minWidth: 44, minHeight: 44).padding(.horizontal, 6)
                        Capsule().fill(selection == item.id ? PUBOTheme.accent : .clear).frame(height: 3)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier(prefix + item.id)
                    .accessibilityAddTraits(selection == item.id ? .isSelected : [])
            }
        }.padding(.horizontal, 8)
    }
    var body: some View {
        // Center the complete phone tab row when it fits, as H5 does. At large
        // type sizes preserve horizontal scrolling instead of shrinking labels.
        ViewThatFits(in: .horizontal) {
            tabItems.fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity)
            ScrollView(.horizontal) { tabItems }.scrollIndicators(.hidden)
        }.background(PUBOTheme.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
    }
}

struct ChatDateSeparator: View {
    enum Style { case direct, room }
    let pair: ChatDays.Pair
    let style: Style
    @ScaledMetric(relativeTo: .caption) private var labelSize = 11.9
    var body: some View {
        Group {
            if style == .direct {
                Text(pair.privateText).padding(.vertical, 8).opacity(0.7)
            } else {
                HStack(spacing: labelSize * 0.5) {
                    Image(systemName: "chevron.up")
                    Text(pair.older)
                    Rectangle().fill(PUBOTheme.divider).frame(width: 1, height: labelSize)
                    Text(pair.newer)
                    Image(systemName: "chevron.down")
                }
                .padding(.vertical, labelSize * 0.5).padding(.horizontal, labelSize)
                .overlay(Capsule().strokeBorder(PUBOTheme.divider, lineWidth: 0.5).allowsHitTesting(false))
                .opacity(0.75)
            }
        }
        .font(.system(size: labelSize)).foregroundStyle(PUBOTheme.text)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("日期 " + (style == .direct ? pair.privateText : pair.chronologicalText))
        .accessibilityAddTraits(.isStaticText)
    }
}

struct ChatRelativeTime: View {
    let date: Date
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { tick in
            Text(label(at: tick.date))
        }
    }
    private func label(at now: Date) -> String {
        ChatRelativeTimePolicy.label(date: date, now: now)
    }
}

/// Only stream insertions opt in; initial pages, restored rows and search context stay still.
struct ChatMessageEntrance: ViewModifier {
    let animate: Bool
    let distance: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.opacity(animate && !appeared ? 0 : 1).offset(y: animate && !appeared && !reduced ? distance : 0)
            .onAppear {
                guard animate else { appeared = true; return }
                withAnimation(.timingCurve(0, 0.5, 0.5, 1, duration: 0.2)) { appeared = true }
            }
    }
}

extension View {
    @ViewBuilder func chatNavigationTitle(_ title: String, embedded: Bool) -> some View {
        if embedded { self } else { self.navigationTitle(title) }
    }
}

struct ChatReactionFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(subviews, width: proposal.width ?? 320).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, used: CGFloat = 0
        var points: [CGPoint] = []
        for item in subviews {
            let size = item.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + 8; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 8
            used = max(used, x - 8); rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: min(width, used), height: y + rowHeight), points)
    }
}
