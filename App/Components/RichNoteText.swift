import SwiftUI
import SDWebImage
import PUBOCore

/// TextKit lays out links and emoji attachments in one selectable text flow.
/// Animated attachments are native views positioned over the reserved glyph rects.
struct RichNoteText: UIViewRepresentable {
    let parts: [String]
    let urls: [String: URL]
    let images: [String: UIImage]
    let playing: Bool
    let identifier: String
    let openURL: (URL) -> Void
    var onTap: (() -> Void)?
    var appearance: NoteAppearance = .standard
    var fitsContentWidth = false
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> AnimatedTextView {
        let view = AnimatedTextView()
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true; view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator; view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: AnimatedTextView, context: Context) {
        context.coordinator.openURL = openURL; context.coordinator.onTap = onTap; context.coordinator.view = view
        // H5's 14px base is 0.9em in a phone-width note container.
        let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: UIFont.systemFont(ofSize: 12.6))
        let imageKey = urls.keys.sorted().map { key in key + "=" + (images[key].map { String(describing: ObjectIdentifier($0)) } ?? "pending") }.joined(separator: "|")
        let renderKey = parts.joined(separator: "\u{001f}") + imageKey + String(describing: font.pointSize) + appearance.rawValue
        if context.coordinator.renderKey != renderKey {
        let color = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 222/255, green: 231/255, blue: 228/255, alpha: 1) : UIColor(white: 103/255, alpha: 1) }
        let output = NSMutableAttributedString(string: "")
        for part in parts {
            if let key = urls.keys.first(where: { $0.hasPrefix(part + "https://") }), let image = images[key] {
                let attachment = NSTextAttachment(); attachment.image = image
                let height = font.pointSize * (appearance.isTimeline ? 2 : 1.8)
                let width = height * min(4, max(0.25, image.size.width / max(1, image.size.height)))
                attachment.bounds = CGRect(x: 0, y: font.descender - 1, width: width, height: height)
                let string = NSMutableAttributedString(attachment: attachment)
                if let animated = image as? SDAnimatedImage, animated.animatedImageFrameCount > 1 {
                    // The animated overlay owns the pixels; otherwise a transparent
                    // frame reveals the static first frame underneath it.
                    if appearance.isTimeline { attachment.image = UIImage() }
                    string.addAttribute(.init("PUBOAnimatedImage"), value: animated, range: NSRange(location: 0, length: 1))
                }
                output.append(string)
            } else {
                let value = (try? AttributedString(markdown: NativeLink.linkedText(part), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(part)
                for run in value.runs {
                    var traits = UIFontDescriptor.SymbolicTraits()
                    if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { traits.insert(.traitBold) }
                    if run.inlinePresentationIntent?.contains(.emphasized) == true { traits.insert(.traitItalic) }
                    let runFont = traits.isEmpty ? font : UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: font.pointSize)
                    var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color]
                    if let link = run.link { attributes[.link] = link }
                    if run.inlinePresentationIntent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    var display = String(value[run.range].characters)
                    if appearance.isTimeline, let link = run.link, link.host == Endpoint.origin.host,
                       display == link.absoluteString {
                        display = link.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if display.isEmpty { display = link.host ?? display }
                        if let query = link.query { display += "?" + query }
                        if let fragment = link.fragment { display += "#" + fragment }
                    }
                    output.append(NSAttributedString(string: display, attributes: attributes))
                }
            }
        }
        if appearance.isTimeline {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = font.pointSize * 1.35
            paragraph.lineBreakMode = .byWordWrapping
            output.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: output.length))
        }
        view.attributedText = output; view.rebuildAnimations()
        context.coordinator.renderKey = renderKey
        }
        view.linkTextAttributes = [.foregroundColor: UIColor(red: 0.42, green: 0.63, blue: 0.65, alpha: 1)]
        view.playing = playing; view.accessibilityIdentifier = identifier
        view.accessibilityTraits = onTap == nil ? .staticText : [.staticText, .button]
        view.setNeedsLayout()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AnimatedTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        var fittedWidth = width
        if fitsContentWidth {
            let measured = uiView.attributedText.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            fittedWidth = min(width, max(1, ceil(measured.width)))
        }
        return CGSize(width: fittedWidth, height: max(1, uiView.sizeThatFits(CGSize(width: fittedWidth, height: .greatestFiniteMagnitude)).height))
    }
    static func dismantleUIView(_ view: AnimatedTextView, coordinator: Coordinator) { view.clearAnimations(); view.delegate = nil }
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var view: AnimatedTextView?
        var renderKey: String?
        var openURL: ((URL) -> Void)?
        var onTap: (() -> Void)?
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool { openURL?(URL); return false }
        private func link(at point: CGPoint, view: UITextView) -> Bool {
            guard view.attributedText.length > 0 else { return false }
            let glyph = view.layoutManager.glyphIndex(for: point, in: view.textContainer)
            guard glyph < view.layoutManager.numberOfGlyphs,
                  view.layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer).insetBy(dx: -2, dy: -2).contains(point) else { return false }
            let index = view.layoutManager.characterIndexForGlyph(at: glyph)
            return index < view.attributedText.length && view.attributedText.attribute(.link, at: index, effectiveRange: nil) != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { guard let view else { return false }; return onTap != nil && !link(at: touch.location(in: view), view: view) }
        @objc func tap(_ recognizer: UITapGestureRecognizer) { if recognizer.state == .ended { onTap?() } }
    }
    final class AnimatedTextView: UITextView {
        var playing = false
        private var overlays: [(NSRange, ProtectedGIFImageView, SDAnimatedImage)] = []
        init() {
            // Use our designated initializer so Swift-owned animation state is initialized.
            // An explicit TextKit 1 stack also keeps attachment glyph positions consistent.
            let storage = NSTextStorage()
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            container.widthTracksTextView = true
            manager.addTextContainer(container); storage.addLayoutManager(manager)
            super.init(frame: .zero, textContainer: container)
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        func clearAnimations() { for (_, view, _) in overlays { view.clear(); view.removeFromSuperview() }; overlays = [] }
        func rebuildAnimations() {
            clearAnimations()
            attributedText.enumerateAttribute(.init("PUBOAnimatedImage"), in: NSRange(location: 0, length: attributedText.length)) { value, range, _ in
                guard let image = value as? SDAnimatedImage else { return }
                let view = ProtectedGIFImageView(frame: .zero); view.isUserInteractionEnabled = false; view.isAccessibilityElement = false; view.maxBufferSize = 1024 * 1024
                addSubview(view); overlays.append((range, view, image))
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            for (range, imageView, image) in overlays {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                imageView.frame = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                let visible = window != nil && convert(bounds, to: nil).intersects(UIScreen.main.bounds)
                imageView.configure(image, playing: playing && visible, identifier: "timeline.inlineEmoji", open: nil)
            }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { for (_, view, _) in overlays { view.stopAnimating() } } }
    }
}
