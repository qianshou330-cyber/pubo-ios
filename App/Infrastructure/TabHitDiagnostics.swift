import SwiftUI
#if DEBUG
import UIKit
import OSLog

/// Synthetic-only UIKit observations. Never dispatches a touch or supplies test readiness.
@MainActor enum TabHitDiagnostics {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
        !ProcessInfo.processInfo.arguments.contains("--isolated-backend") &&
        (ProcessInfo.processInfo.arguments.contains("--chat-preview-failure") ||
         ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--video-poster-fixture=") }))
    static var started = false
    static let logger = Logger(subsystem: "com.pubo.tabhit.diagnostics", category: "window-hit")
    static func marker(_ event: String) {
        let message = "event=\(event) pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(ProcessInfo.processInfo.systemUptime)"
        logger.notice("\(message, privacy: .public)")
    }
    static func kind(_ view: UIView?) -> String {
        guard let view else { return "none" }
        if view is UIWindow { return "window" }
        if view is UIButton { return "button" }
        if view is UIControl { return "control" }
        if view is UIScrollView { return "scroll" }
        if view is UILabel { return "label" }
        if view is UIImageView { return "image" }
        return "view"
    }
    static func sample(_ anchor: UIView, index: Int) {
        guard let window = anchor.window, let scene = window.windowScene else { marker("noWindow"); return }
        let rect = anchor.convert(anchor.bounds, to: window)
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }), rect.width > 0, rect.height > 0 else { marker("invalidGeometry"); return }
        // Fixed tab order; these are BAR-quarter centers, not AX-derived button frames.
        for tab in [0, 2] {
            let point = CGPoint(x: rect.minX + rect.width * (CGFloat(tab) + 0.5) / 4, y: rect.midY)
            // Diagnostic level sort only; equal-level order is NOT touch routing order.
            let windows = scene.windows.sorted { $0.windowLevel.rawValue > $1.windowLevel.rawValue }
            for (rank, candidate) in windows.prefix(8).enumerated() {
                let local = candidate.convert(point, from: window)
                let hit = candidate.hitTest(local, with: nil)
                var path: [String] = [], cursor = hit
                for _ in 0..<12 {
                    guard let view = cursor else { break }
                    path.append("\(kind(view)):\(view.isHidden):\(view.isUserInteractionEnabled):\(view.alpha)")
                    cursor = view.superview
                }
                let message = "event=sample pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(ProcessInfo.processInfo.systemUptime) sample=\(index) tab=\(tab) scene=\(scene.activationState.rawValue) windows=\(scene.windows.count) levelSortIndex=\(rank) key=\(candidate.isKeyWindow) own=\(candidate === window) level=\(candidate.windowLevel.rawValue) hidden=\(candidate.isHidden) interaction=\(candidate.isUserInteractionEnabled) alpha=\(candidate.alpha) point=\(local) bar=\(rect) hitPath=\(path)"
                logger.notice("\(message, privacy: .public)")
            }
        }
    }
}

private struct TabHitAnchor: UIViewRepresentable {
    final class Anchor: UIView {
        var sampling: Task<Void, Never>?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, TabHitDiagnostics.enabled, !TabHitDiagnostics.started else { return }
            TabHitDiagnostics.started = true
            TabHitDiagnostics.marker("start")
            sampling = Task { @MainActor [weak self] in
                let began = ProcessInfo.processInfo.systemUptime
                defer { TabHitDiagnostics.marker("end") }
                for index in 0..<30 {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime - began <= 120,
                          let self, self.window != nil else { TabHitDiagnostics.marker("cancelledDeadlineOrRemoved"); return }
                    TabHitDiagnostics.sample(self, index: index)
                }
            }
        }
    }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor(); view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false; view.accessibilityElementsHidden = true
        return view
    }
    func updateUIView(_ uiView: Anchor, context: Context) {}
    static func dismantleUIView(_ uiView: Anchor, coordinator: ()) { uiView.sampling?.cancel() }
}
#endif

struct TabHitDiagnosticsModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if TabHitDiagnostics.enabled {
            content.background { TabHitAnchor().allowsHitTesting(false).accessibilityHidden(true) }
        } else { content }
        #else
        content
        #endif
    }
}
