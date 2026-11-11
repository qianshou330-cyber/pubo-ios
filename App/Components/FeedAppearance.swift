import SwiftUI

/// Appearance is deliberately independent of NoteCard's stream ownership.
enum NoteAppearance: String {
    case standard, timeline
    var isTimeline: Bool { self == .timeline }
}

struct FeedIcon: View {
    let name: String
    var size: CGFloat = 16.3
    var body: some View {
        Image("FeedIcon-" + name).renderingMode(.template).resizable()
            .scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct NoteIcon: View {
    let system: String
    let web: String
    let appearance: NoteAppearance
    var size: CGFloat = 16.3
    var body: some View {
        if appearance.isTimeline { FeedIcon(name: web, size: size) }
        else { Image(systemName: system) }
    }
}

enum FeedColors {
    static let action = PUBOTheme.adaptive(0x959595, 0xa3aca8)
    static let reaction = PUBOTheme.adaptive(0xf2f2f2, 0x24322e)
}

/// Keep four discrete hit boxes. Shrink only the gaps, then wrap for accessibility.
struct FeedActionsLayout: Layout {
    var spacing: CGFloat = 28
    private func layout(_ subviews: Subviews, width: CGFloat) -> ([CGPoint], CGSize) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = sizes.reduce(0) { $0 + $1.width }
        let gap = min(spacing, max(0, (width - total) / CGFloat(max(1, sizes.count - 1))))
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > width + 0.5 { x = 0; y += line + 2; line = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + gap; line = max(line, size.height)
        }
        return (points, CGSize(width: width, height: y + line))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews, width: proposal.width ?? 328).1
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = layout(subviews, width: bounds.width).0
        for (i, point) in points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
}

extension View {
    @ViewBuilder
    func feedHeaderTarget(_ appearance: NoteAppearance, alignment: Alignment) -> some View {
        if appearance.isTimeline {
            frame(minWidth: 44, minHeight: 44, alignment: alignment).contentShape(Rectangle())
        } else {
            self
        }
    }

    @ViewBuilder
    func feedHitShape(_ appearance: NoteAppearance) -> some View {
        if appearance.isTimeline { contentShape(Rectangle()) } else { self }
    }
}
