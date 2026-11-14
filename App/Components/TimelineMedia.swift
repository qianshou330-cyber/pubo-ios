import SwiftUI
import ImageIO
import OSLog
import SDWebImage
import PUBOCore

// Fixed stage names only: never emit account IDs, URLs, tokens or media contents.
enum PublicMediaDiagnostics {
    enum Stage: String {
        case decoderRegistrationStarted, decoderRegistrationFinished, decodeStarted, decodeFinished
        case posterStarted, posterCached, thumbnailStarted, thumbnailReady, thumbnailFailed
        case sourceUnavailable, budgetWaiting, budgetAcquired, generatorStarted, generatorReady, generatorFailed, cancelled
    }
    static func emit(_ stage: Stage) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        Logger(subsystem: "com.pubo.media.diagnostics", category: "preview").notice("stage=\(stage.rawValue, privacy: .public)")
        #endif
    }
}

enum PublicImageDecoder {
    private static let registered: Void = { SDImageCodersManager.shared.addCoder(SDImageAWebPCoder.shared) }()
    static func decode(_ data: Data, maxPixel: Int = 720) async throws -> UIImage {
        PublicMediaDiagnostics.emit(.decoderRegistrationStarted)
        _ = registered
        PublicMediaDiagnostics.emit(.decoderRegistrationFinished)
        let task = Task<UIImage, Error>.detached(priority: .userInitiated) {
            PublicMediaDiagnostics.emit(.decodeStarted)
            defer { PublicMediaDiagnostics.emit(.decodeFinished) }
            try Task.checkCancellation()
            guard data.count <= 50 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0, CGImageSourceGetCount(source) <= 2_000,
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? NSNumber, let h = props[kCGImagePropertyPixelHeight] as? NSNumber,
                  w.doubleValue > 0, h.doubleValue > 0, w.doubleValue * h.doubleValue <= 40_000_000 else { throw APIError.invalidResponse }
            if CGImageSourceGetCount(source) > 1,
               let image = SDAnimatedImage(data: data, scale: 1, options: [.decodeThumbnailPixelSize: NSValue(cgSize: CGSize(width: maxPixel, height: maxPixel)), .decodePreserveAspectRatio: true]) { return image }
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary) else { throw APIError.invalidResponse }
            return UIImage(cgImage: frame)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    static func data(_ url: URL, limit: Int = 50 * 1024 * 1024) async throws -> Data {
        guard safeMediaURL(url.absoluteString) != nil else { throw APIError.invalidResponse }
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 60
        let client = URLSession(configuration: configuration); defer { client.invalidateAndCancel() }
        let (bytes, response) = try await client.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, safeMediaURL(response.url?.absoluteString) != nil,
              response.expectedContentLength <= limit else { throw APIError.invalidResponse }
        var result = Data(); result.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if result.count % 16384 == 0 { try Task.checkCancellation() }
            guard result.count < limit else { throw APIError(code: "FILE_TOO_LARGE", message: "媒体超过预览限制。") }
            result.append(byte)
        }
        return result
    }
}

struct PublicAnimationSurface: UIViewRepresentable {
    let image: SDAnimatedImage
    let playing: Bool
    var open: (() -> Void)? = nil
    var identifier = "timeline.animatedImage"
    func makeUIView(context: Context) -> ProtectedGIFImageView { ProtectedGIFImageView(frame: .zero) }
    func updateUIView(_ view: ProtectedGIFImageView, context: Context) { view.configure(image, playing: playing, identifier: identifier, open: open); view.isUserInteractionEnabled = open != nil }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProtectedGIFImageView, context: Context) -> CGSize? { CGSize(width: proposal.width ?? 24, height: proposal.height ?? 24) }
    static func dismantleUIView(_ view: ProtectedGIFImageView, coordinator: ()) { view.clear() }
}

struct PublicAnimatedAsset: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    let url: URL
    var fit = true
    var emoji = false
    var open: (() -> Void)? = nil
    var emojiHeight: CGFloat? = nil
    var animationIdentifier = "timeline.animatedImage"
    @State private var image: UIImage?
    @State private var error = false
    @State private var visible = false
    @State private var retry = 0
    var body: some View {
        Group {
            if let animated = image as? SDAnimatedImage, animated.animatedImageFrameCount > 1 {
                PublicAnimationSurface(image: animated, playing: visible && phase == .active, open: open, identifier: animationIdentifier)
            } else if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill) }
            else if error { Button { retry += 1 } label: { Image(systemName: "arrow.clockwise").font(.caption) }.accessibilityLabel("重试图片") }
            else { ProgressView().controlSize(.small) }
        }.frame(width: emojiHeight.map { $0 * min(4, max(0.25, (image?.size.width ?? 1) / max(1, image?.size.height ?? 1))) }, height: emojiHeight).background(GeometryReader { g in
            Color.clear.onAppear { visible = g.frame(in: .global).intersects(UIScreen.main.bounds) }
                .onChange(of: g.frame(in: .global)) { _, rect in visible = rect.intersects(UIScreen.main.bounds) }
        }).task(id: "\(url)-\(session.generation)-\(retry)") {
            image = nil; error = false; let epoch = session.generation
            let cacheKey = PublicPreviewCache.shared.key("image:\(emoji):" + url.absoluteString, generation: String(describing: epoch))
            if let cached = PublicPreviewCache.shared.image(cacheKey) { image = cached; return }
            do {
                let data: Data
                #if DEBUG
                if session.testMode && !session.isolatedBackend {
                    guard let fixture = TimelineTestFixtures.media(url) else { throw APIError.invalidResponse }; data = fixture
                } else { data = try await PublicImageDecoder.data(url, limit: emoji ? 2_000_000 : 50 * 1024 * 1024) }
                #else
                data = try await PublicImageDecoder.data(url, limit: emoji ? 2_000_000 : 50 * 1024 * 1024)
                #endif
                let decoded = try await PublicImageDecoder.decode(data, maxPixel: emoji ? 100 : 720)
                guard epoch == session.generation, !Task.isCancelled else { return }; image = decoded
                // Never freeze GIF/WebP animation into a single cached frame.
                if !(decoded is SDAnimatedImage) { PublicPreviewCache.shared.insert(decoded, key: cacheKey) }
            } catch { if !Task.isCancelled { self.error = true } }
        }.onDisappear { visible = false; image = nil }
    }
}

struct PublicMediaGrid: View {
    let files: [Record]
    let noteID: String
    var body: some View {
        if files.count == 1 {
            TimelineMediaItem(file: files[0], noteID: noteID)
        } else if files.count > 1 {
            GeometryReader { geometry in
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    let frame = cell(index, in: geometry.size)
                    TimelineMediaItem(file: file, noteID: noteID, compact: true, cellSize: frame.size)
                        .frame(width: frame.width, height: frame.height).clipped()
                        .position(x: frame.midX, y: frame.midY)
                }
            }.aspectRatio(files.count <= 4 ? 16.0 / 9 : 32.0 / (9 * ceil(Double(files.count) / 2)), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    private func cell(_ index: Int, in size: CGSize) -> CGRect {
        let gap: CGFloat = 8
        if files.count == 3 {
            let left = max(0, size.width - gap) * 2 / 3
            if index == 0 { return CGRect(x: 0, y: 0, width: left, height: size.height) }
            let height = max(0, size.height - gap) / 2
            return CGRect(x: left + gap, y: CGFloat(index - 1) * (height + gap), width: max(0, size.width - left - gap), height: height)
        }
        let rows = ceil(CGFloat(files.count) / 2)
        let width = max(0, size.width - gap) / 2, height = max(0, size.height - gap * (rows - 1)) / rows
        return CGRect(x: CGFloat(index % 2) * (width + gap), y: CGFloat(index / 2) * (height + gap), width: width, height: height)
    }
}

struct TimelineMediaItem: View {
    @Environment(AppSession.self) private var session
    let file: Record
    let noteID: String
    var compact = false
    var cellSize: CGSize? = nil
    @State private var revealed = false
    @State private var preview = false
    private var hidden: Bool { file["isSensitive"].bool && !revealed }
    private var mime: String { file["type"].string ?? "" }
    private var mediaURL: URL? { safeMediaURL(["image/gif", "image/png", "image/apng", "image/webp"].contains(mime) ? file["url"].string : file["thumbnailUrl"].string ?? file["url"].string) }
    private var ratio: CGFloat {
        if compact { return 1 }
        let width = file["properties"]["width"].int, height = file["properties"]["height"].int
        // H5's default single-image frame is at least 16:9, preserving wider images.
        return width > 0 && height > 0 ? max(16.0 / 9, CGFloat(width) / CGFloat(height)) : 16.0 / 9
    }
    var body: some View {
        Group {
            if hidden {
                Button { revealed = true } label: {
                    VStack(spacing: 6) { Image(systemName: "eye.slash"); Text("敏感媒体").bold(); Text("点击展开").font(.caption) }.frame(maxWidth: .infinity, minHeight: cellSize == nil ? (compact ? 120 : 150) : 0, maxHeight: .infinity).background(PUBOTheme.button)
                }.buttonStyle(.plain).accessibilityIdentifier("media.reveal." + file.id)
            } else if mime.hasPrefix("image/"), let url = mediaURL {
                PublicAnimatedAsset(url: url, open: { preview = true }, animationIdentifier: "media.animation." + file.id).aspectRatio(cellSize == nil ? ratio : nil, contentMode: .fit).frame(width: cellSize?.width, height: cellSize?.height).frame(maxHeight: cellSize == nil ? 420 : nil).background(TimelineMediaBackdrop()).clipped()
                    .overlay(alignment: .topLeading) { if mime == "image/gif" { Text("GIF").font(.system(size: 10)).foregroundStyle(.white).padding(3).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 3)).padding(5) } }
                    .contentShape(Rectangle()).onTapGesture { preview = true }.accessibilityLabel(file["comment"].string ?? "查看图片").accessibilityAddTraits(.isButton).accessibilityIdentifier("media.open." + file.id)
            } else if mime.hasPrefix("video/") || mime.hasPrefix("audio/") {
                Button { preview = true } label: {
                    ZStack {
                        if mime.hasPrefix("video/") { PublicVideoPoster(file: file, ratio: ratio) }
                        else if let url = safeMediaURL(file["thumbnailUrl"].string) { PublicAnimatedAsset(url: url).aspectRatio(ratio, contentMode: .fit) }
                        else { PUBOTheme.button.frame(height: mime.hasPrefix("audio/") ? 72 : 160) }
                        // Video lays out its own control alongside loading/failure text.
                        if mime.hasPrefix("audio/") {
                            Image(systemName: "play.fill").font(.title2).foregroundStyle(.white).padding(18).background(PUBOTheme.accent, in: Circle())
                        }
                    }
                }.buttonStyle(.plain).accessibilityLabel(mime.hasPrefix("audio/") ? "播放音频" : "播放视频").accessibilityIdentifier("media.open." + file.id)
            } else if let url = safeMediaURL(file["url"].string) { Link(file["name"].string ?? "打开附件", destination: url).font(.caption) }
        }.frame(width: cellSize?.width, height: cellSize?.height).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            .sheet(isPresented: $preview) { PublicAttachmentPreview(file: file, allowSensitive: revealed) }
            .onChange(of: file) { _, _ in revealed = false; preview = false }
            .onChange(of: session.generation) { _, _ in revealed = false; preview = false }
            .onDisappear { revealed = false }
    }
}

struct UserInlineBadges: View {
    let user: Record
    var appearance: NoteAppearance = .standard
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize = 12.6
    var body: some View { HStack(spacing: 2) { ForEach(Record.list(user["badgeRoles"]).prefix(3)) { role in
        if let url = safeMediaURL(role["iconUrl"].string) {
            Group {
                if appearance.isTimeline { PublicAnimatedAsset(url: url, emoji: true, emojiHeight: badgeSize) }
                else { PublicAnimatedAsset(url: url, emoji: true).frame(width: 12, height: 12) }
            }.accessibilityLabel(role["name"].string ?? "认证")
        }
    } } }
}

struct ReactionImage: View {
    @Environment(AppSession.self) private var session
    let reaction: String
    var emojis: JSONValue = .null
    var emojiHeight: CGFloat = 24
    var unicodeSize: CGFloat = 18
    private var name: String { reaction.trimmingCharacters(in: CharacterSet(charactersIn: ":")).replacingOccurrences(of: "@.", with: "") }
    private var url: URL? { safeMediaURL(emojis[name].string ?? session.emojis.first(where: { $0["name"].string == name })?["url"].string) }
    var body: some View {
        if reaction.hasPrefix(":"), let url { PublicAnimatedAsset(url: url, emoji: true, emojiHeight: emojiHeight) }
        else { Text(reaction).font(.system(size: unicodeSize)).lineLimit(1) }
    }
}

struct FlowReactionLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { positions(width: proposal.width ?? 320, subviews: subviews).1 }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = positions(width: bounds.width, subviews: subviews)
        for (index, point) in result.0.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func positions(width: CGFloat, subviews: Subviews) -> ([CGPoint], CGSize) {
        var points: [CGPoint] = []; var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += height + 4; height = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 4; height = max(height, size.height)
        }
        return (points, CGSize(width: width, height: y + height))
    }
}

struct NoteLinkPreviews: View {
    @Environment(AppSession.self) private var session
    let text: String
    var active: Bool
    var appearance: NoteAppearance = .standard
    @ScaledMetric(relativeTo: .caption) private var titleSize = 10
    @ScaledMetric(relativeTo: .caption2) private var summarySize = 8
    @ScaledMetric(relativeTo: .caption2) private var domainHeight = 16
    @State private var previews: [JSONValue] = []
    private var links: [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return Array(Set(detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> URL? in
            guard let url = match.url, ["https", "http"].contains(url.scheme), url.user == nil, url.password == nil else { return nil }; return url
        })).sorted { $0.absoluteString < $1.absoluteString }.prefix(3).map { $0 }
    }
    var body: some View {
        VStack(spacing: 6) { ForEach(Array(previews.enumerated()), id: \.offset) { _, preview in
            if let url = NativeLink.publicURL(preview["url"].string ?? "") {
                Link(destination: url) { Group {
                    if appearance.isTimeline {
                        HStack(spacing: 0) {
                            Group {
                                if !preview["sensitive"].bool, let thumb = safeMediaURL(preview["thumbnail"].string) { PublicAnimatedAsset(url: thumb).scaledToFill() }
                                else { Color.clear }
                            }.frame(width: 56, height: 52).clipped().accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preview["title"].string ?? url.host ?? "网页").font(.system(size: titleSize, weight: .bold)).lineLimit(2)
                                Text(preview["description"].string ?? "").font(.system(size: summarySize)).lineLimit(2)
                                Text(url.host ?? "").font(.system(size: summarySize)).frame(minHeight: domainHeight)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                        }.frame(minHeight: 52).foregroundStyle(PUBOTheme.text).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PUBOTheme.divider))
                    } else { HStack(spacing: 8) {
                    if !preview["sensitive"].bool, let thumb = safeMediaURL(preview["thumbnail"].string) { PublicAnimatedAsset(url: thumb).frame(width: 62, height: 62).clipped() }
                    VStack(alignment: .leading, spacing: 4) { Text(preview["title"].string ?? url.host ?? "网页").font(.caption.bold()).lineLimit(2); Text(preview["description"].string ?? "").font(.caption2).lineLimit(2); Text(url.host ?? "").font(.system(size: 9)) }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(8).foregroundStyle(PUBOTheme.text).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PUBOTheme.divider)) }
                } }
            }
        } }.task(id: text + String(active)) {
            previews = []; guard active else { return }; let epoch = session.generation
            for link in links {
                do {
                    let value: JSONValue
                    #if DEBUG
                    if session.testMode && !session.isolatedBackend { value = .object(["url": .string(link.absoluteString), "title": .string("下载 PUBO Android 版"), "description": .string("PUBO 官方下载页面")]) }
                    else { value = try await fetch(link) }
                    #else
                    value = try await fetch(link)
                    #endif
                    guard epoch == session.generation, !Task.isCancelled else { return }; previews.append(value)
                } catch { }
            }
        }
    }
    private func fetch(_ url: URL) async throws -> JSONValue {
        var endpoint = URLComponents(url: Endpoint.origin.appendingPathComponent("url"), resolvingAgainstBaseURL: false)!
        endpoint.queryItems = [.init(name: "url", value: url.absoluteString), .init(name: "lang", value: "zh-CN")]
        return try JSONDecoder().decode(JSONValue.self, from: await PublicImageDecoder.data(endpoint.url!, limit: 512_000))
    }
}
