#if DEBUG
import SwiftUI
import UIKit

/// Passive fixture-only instrumentation. Never sets a delegate, installs a
/// recognizer, changes scrolling, or starts/ends a refresh.
struct RefreshScrollProbe: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.onAttach = { [weak coordinator = context.coordinator] view in coordinator?.attach(from: view) }
        return view
    }
    func updateUIView(_ view: ProbeView, context: Context) { context.coordinator.attach(from: view) }
    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        view.onAttach = nil
        coordinator.detach()
    }
    final class ProbeView: UIView {
        var onAttach: ((UIView) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); onAttach?(self) }
        override func layoutSubviews() { super.layoutSubviews(); onAttach?(self) }
    }
    final class Coordinator: NSObject {
        private weak var scroll: UIScrollView?
        private weak var refresh: UIRefreshControl?
        private var offsetObservation: NSKeyValueObservation?
        func attach(from view: UIView) {
            guard view.window != nil else { detach(); return }
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--ui-testing"), arguments.contains("--refreshable-feed") else { return }
            var ancestor = view.superview
            while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
            guard let found = ancestor as? UIScrollView else { return }
            guard scroll !== found else { bindRefreshControl(); return }
            detach()
            scroll = found
            found.panGestureRecognizer.addTarget(self, action: #selector(panChanged))
            bindRefreshControl()
            offsetObservation = found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                self?.bindRefreshControl()
                guard let self, let scroll = self.scroll else { return }
                if scroll.isDragging || scroll.refreshControl?.isRefreshing == true { self.sample("offset") }
            }
            sample("attached")
        }
        func detach() {
            offsetObservation?.invalidate(); offsetObservation = nil
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged))
            refresh?.removeTarget(self, action: #selector(refreshChanged), for: .valueChanged)
            scroll = nil; refresh = nil
        }
        private func bindRefreshControl() {
            guard refresh !== scroll?.refreshControl else { return }
            refresh?.removeTarget(self, action: #selector(refreshChanged), for: .valueChanged)
            refresh = scroll?.refreshControl
            refresh?.addTarget(self, action: #selector(refreshChanged), for: .valueChanged)
        }
        @objc private func panChanged() {
            bindRefreshControl()
            // Offset observations carry movement; keep terminal events available.
            if scroll?.panGestureRecognizer.state != .changed { sample("pan") }
        }
        @objc private func refreshChanged() { sample("valueChanged") }
        private func sample(_ event: String) {
            guard let scroll else { return }
            RefreshDiagnostics.shared.recordScroll(event: event,
                offsetY: Double(scroll.contentOffset.y), insetTop: Double(scroll.adjustedContentInset.top),
                panState: scroll.panGestureRecognizer.state.rawValue,
                refreshing: scroll.refreshControl?.isRefreshing ?? false,
                hasRefreshControl: scroll.refreshControl != nil)
        }
    }
}
#endif
