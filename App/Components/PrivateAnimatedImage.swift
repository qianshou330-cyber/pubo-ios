import SwiftUI
import ImageIO
import SDWebImage
import PUBOCore

/// Decode only bytes already returned by the protected attachment endpoint.
/// No downloader, URL loader, shared image cache, or disk cache is involved.
enum PrivateImageDecoder {
    private static let queue = DispatchQueue(label: "pubo.private-image.decode", qos: .userInitiated)
    static func isGIF(_ data: Data) -> Bool {
        let signature = String(data: data.prefix(6), encoding: .ascii)
        return signature == "GIF87a" || signature == "GIF89a"
    }
    static func decode(_ data: Data, maxPixel: Int) async throws -> UIImage {
        try Task.checkCancellation()
        let result: UIImage = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    do {
                        guard data.count <= 50 * 1024 * 1024,
                              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                              CGImageSourceGetCount(source) > 0, CGImageSourceGetCount(source) <= 2000,
                              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                              width.doubleValue > 0, height.doubleValue > 0,
                              width.doubleValue * height.doubleValue <= 40_000_000 else { throw APIError.invalidResponse }
                        if isGIF(data), CGImageSourceGetCount(source) > 1 {
                            let options: [SDImageCoderOption: Any] = [
                                .decodeThumbnailPixelSize: NSValue(cgSize: CGSize(width: CGFloat(maxPixel), height: CGFloat(maxPixel))),
                                .decodePreserveAspectRatio: true
                            ]
                            guard let image = SDAnimatedImage(data: data, scale: 1, options: options), image.animatedImageFrameCount > 1 else { throw APIError.invalidResponse }
                            continuation.resume(returning: image)
                        } else {
                            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary) else { throw APIError.invalidResponse }
                            continuation.resume(returning: UIImage(cgImage: frame))
                        }
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
        try Task.checkCancellation()
        return result
    }
}

/// Frame timing and GIF disposal/transparency are handled by the pinned native decoder.
/// Only a bounded frame buffer is retained; all frames are never eagerly expanded.
final class ProtectedGIFImageView: SDAnimatedImageView {
    private var requestedPlayback = false
    private var effectivePlayback = false
    var open: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        autoPlayAnimatedImage = false
        clearBufferWhenStopped = true
        resetFrameIndexWhenStopped = false
        // ImageIO already converts GIF repetition metadata to total plays on iOS.
        // Preserve the decoder's loop count; adding one here would play an extra cycle.
        shouldCustomLoopCount = false
        playbackRate = 1
        maxBufferSize = 8 * 1024 * 1024
        runLoopMode = .common
        contentMode = .scaleAspectFit
        clipsToBounds = true
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "GIF 动画"
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openImage)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func openImage() { open?() }
    override func accessibilityActivate() -> Bool { guard let open else { return false }; open(); return true }
    func configure(_ value: SDAnimatedImage, playing: Bool, identifier: String, open: (() -> Void)?) {
        if image !== value {
            stopAnimating(); effectivePlayback = false
            image = value
        }
        self.open = open
        accessibilityIdentifier = identifier
        accessibilityTraits = open == nil ? [.image] : [.image, .button]
        requestedPlayback = playing
        reconcile()
    }
    private func reconcile() {
        let next = requestedPlayback && window != nil && !isHidden
        guard next != effectivePlayback else { return }
        effectivePlayback = next
        if next { startAnimating() } else { stopAnimating() }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); reconcile() }
    func clear() { requestedPlayback = false; effectivePlayback = false; stopAnimating(); image = nil; open = nil }
    override var accessibilityValue: String? {
        get {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--gif-preview") {
                return "frame=\(currentFrameIndex);loops=\(currentLoopCount);playing=\(isAnimating);width=\(image?.cgImage?.width ?? 0);height=\(image?.cgImage?.height ?? 0);buffer=\(maxBufferSize)"
            }
            #endif
            return isAnimating ? "正在播放" : "已暂停或播放完毕"
        }
        set { super.accessibilityValue = newValue }
    }
}

private struct GIFSurface: UIViewRepresentable {
    let image: SDAnimatedImage
    let playing: Bool
    let identifier: String
    let open: (() -> Void)?
    func makeUIView(context: Context) -> ProtectedGIFImageView { ProtectedGIFImageView(frame: .zero) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProtectedGIFImageView, context: Context) -> CGSize? {
        // UIKit's image intrinsic size must not override the conversation bubble's bounds.
        CGSize(width: proposal.width ?? 240, height: proposal.height ?? 220)
    }
    func updateUIView(_ view: ProtectedGIFImageView, context: Context) { view.configure(image, playing: playing, identifier: identifier, open: open) }
    static func dismantleUIView(_ view: ProtectedGIFImageView, coordinator: ()) { view.clear() }
}

private struct ZoomableGIFSurface: UIViewRepresentable {
    let image: SDAnimatedImage
    let playing: Bool
    let identifier: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ZoomableImage.ImageScrollView {
        let scroll = ZoomableImage.ImageScrollView()
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5; scroll.delegate = context.coordinator
        let picture = ProtectedGIFImageView(frame: .zero)
        picture.maxBufferSize = 16 * 1024 * 1024
        scroll.addSubview(picture); scroll.picture = picture; context.coordinator.image = picture
        return scroll
    }
    func updateUIView(_ scroll: ZoomableImage.ImageScrollView, context: Context) {
        context.coordinator.image?.configure(image, playing: playing, identifier: identifier, open: nil)
        if scroll.zoomScale == 1 { context.coordinator.image?.frame = scroll.bounds }
    }
    static func dismantleUIView(_ scroll: ZoomableImage.ImageScrollView, coordinator: Coordinator) { coordinator.image?.clear(); scroll.delegate = nil }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var image: ProtectedGIFImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    }
}

struct PrivateGIFPlayer: View {
    @Environment(\.scenePhase) private var scenePhase
    let image: SDAnimatedImage
    var fullscreen = false
    var open: (() -> Void)? = nil
    @State private var visible = false
    private var identifier: String { fullscreen ? "private.gif.fullscreen" : "private.gif.inline" }
    private var size: CGSize {
        let scale = min(min(240 / max(1, image.size.width), 220 / max(1, image.size.height)), 1)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
    var body: some View {
        Group {
                if fullscreen {
                    ZoomableGIFSurface(image: image, playing: visible && scenePhase == .active, identifier: identifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 200)
                } else {
                    GIFSurface(image: image, playing: visible && scenePhase == .active, identifier: identifier, open: open)
                        .frame(width: size.width, height: size.height).clipShape(RoundedRectangle(cornerRadius: 8))
                }
        }.background(GeometryReader { geometry in
                Color.clear.onAppear { visible = geometry.frame(in: .global).intersects(UIScreen.main.bounds) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in visible = frame.intersects(UIScreen.main.bounds) }
        }).onDisappear { visible = false }
    }
}

struct PrivateInlineImage: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let attachment: Record
    var active = true
    let open: () -> Void
    @State private var image: UIImage?
    @State private var error: String?
    @State private var retry = 0
    private var loadKey: String { "\(session.generation)-\(scenePhase == .active && active)-\(retry)" }
    var body: some View {
        Group {
            if let gif = image as? SDAnimatedImage, gif.animatedImageFrameCount > 1 {
                PrivateGIFPlayer(image: gif, open: open)
            } else if let image {
                Button(action: open) { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel("查看私信图片")
            } else if let error {
                VStack(alignment: .leading) { Text(error).font(.caption).foregroundStyle(.secondary); Button("重试图片") { retry += 1 }.frame(minHeight: 44); Button("查看与保存附件", action: open).frame(minHeight: 44) }
            } else { ProgressView("验证附件权限…").font(.caption) }
        }.task(id: loadKey) {
            image = nil; error = nil
            guard scenePhase == .active, active else { return }
            let owner = session.generation
            do {
                guard attachment["size"].int <= 50 * 1024 * 1024, let token = session.token else { throw APIError.invalidResponse }
                let data = try await session.api.privateAttachment(id: attachment.id, token: token)
                let result = try await PrivateImageDecoder.decode(data, maxPixel: 720)
                guard owner == session.generation, scenePhase == .active, active, !Task.isCancelled else { return }
                image = result
            } catch { if owner == session.generation, scenePhase == .active, !Task.isCancelled { self.error = "图片暂不可用或超过预览限制，请重试或查看附件。" } }
        }.onDisappear { image = nil }
    }
}
