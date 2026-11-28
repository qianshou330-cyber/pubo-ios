import SwiftUI
import UIKit
import PUBOCore

/// Window-level keyboard dismissal and active IME text flushing (including 3rd-party IMEs).
@MainActor
enum KeyboardControl {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow || !window.isHidden {
                window.endEditing(true)
            }
        }
    }

    static func flushActiveTextView(matching identifier: String) -> String? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                if let textView = findTextView(in: window, identifier: identifier) {
                    if textView.markedTextRange != nil {
                        textView.unmarkText()
                    }
                    return textView.text ?? ""
                }
            }
        }
        return nil
    }

    private static func findTextView(in view: UIView, identifier: String) -> UITextView? {
        if let textView = view as? UITextView, textView.accessibilityIdentifier == identifier {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }
}

/// UITextView exposes the same selection on iOS 17 and newer. No keyboard recreation on each edit.
struct CursorTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var focused: Binding<Bool>? = nil
    var enabled = true
    var identifier: String
    var placeholder: String
    var minimumHeight: CGFloat = 44
    var maximumHeight: CGFloat = 140
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator; view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .subheadline); view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor(PUBOTheme.text); view.tintColor = UIColor(PUBOTheme.accent)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 2, bottom: 8, right: 2)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = identifier; view.accessibilityLabel = placeholder
        context.coordinator.observe(view)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.accessibilityIdentifier != identifier { view.accessibilityIdentifier = identifier }
        if view.accessibilityLabel != placeholder { view.accessibilityLabel = placeholder }
        if view.isEditable != enabled { view.isEditable = enabled }
        if view.markedTextRange == nil {
            view.textColor = UIColor(PUBOTheme.text); view.tintColor = UIColor(PUBOTheme.accent)
            if view.text != text {
                context.coordinator.updating = true
                view.text = text
                context.coordinator.updating = false
                view.invalidateIntrinsicContentSize()
            }
            let range = TextInsertion.clamped(selection, in: view.text ?? "")
            if view.selectedRange != range {
                context.coordinator.updating = true
                view.selectedRange = range
                context.coordinator.updating = false
            }
        }
        if let focused {
            let target = focused.wrappedValue
            if target != context.coordinator.lastAppliedFocused {
                context.coordinator.lastAppliedFocused = target
                if target && !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
                else if !target && view.isFirstResponder { view.resignFirstResponder() }
            }
        }
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.stopObserving()
        view.delegate = nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: min(maximumHeight, max(minimumHeight, height)))
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CursorTextEditor
        var updating = false
        var lastAppliedFocused: Bool?
        init(_ parent: CursorTextEditor) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }
        func observe(_ view: UITextView) {
            stopObserving()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTextDidChange(_:)),
                name: UITextView.textDidChangeNotification,
                object: view
            )
        }
        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
        }
        @objc private func handleTextDidChange(_ notification: Notification) {
            guard let view = notification.object as? UITextView else { return }
            syncFromView(view)
        }
        private func syncFromView(_ view: UITextView) {
            guard !updating else { return }
            let current = view.text ?? ""
            if parent.text != current { parent.text = current }
            if parent.selection != view.selectedRange { parent.selection = view.selectedRange }
            view.invalidateIntrinsicContentSize()
        }
        func textViewDidChange(_ view: UITextView) {
            syncFromView(view)
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            // UIKit may notify selection before the text change. Do not redraw with the old binding.
            if !updating && view.text == parent.text { parent.selection = view.selectedRange }
        }
        func textViewDidBeginEditing(_ view: UITextView) {
            lastAppliedFocused = true
            parent.focused?.wrappedValue = true
        }
        func textViewDidEndEditing(_ view: UITextView) {
            lastAppliedFocused = false
            syncFromView(view)
            parent.focused?.wrappedValue = false
        }
    }
}
