import SwiftUI
import AVFoundation
import PUBOCore

/// Public, memory-only previews. Keys include account generation; protected chat
/// attachments never enter this cache. Animated images keep their existing decoder.
@MainActor
final class PublicPreviewCache {
    static let shared = PublicPreviewCache()
    private let images = NSCache<NSString, UIImage>()
    private var epoch: String?
    private init() { images.totalCostLimit = 24 * 1024 * 1024; images.countLimit = 80 }
    func key(_ source: String, generation: String) -> String {
        if epoch != generation { images.removeAllObjects(); epoch = generation }
        return generation + ":" + source
    }
    func image(_ key: String) -> UIImage? { images.object(forKey: key as NSString) }
    func insert(_ image: UIImage, key: String) {
        guard let cg = image.cgImage else { return }
        images.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
    }
}

/// Bound simultaneous fallback extraction instead of creating one decoder for
/// every video in a long feed. Queued work remains cancellation-aware.
actor VideoPosterBudget {
    static let shared = VideoPosterBudget()
    private var active = 0
    func acquire() async throws {
        while active >= 2 { try await Task.sleep(for: .milliseconds(50)) }
        try Task.checkCancellation()
        active += 1
    }
    func release() { active -= 1 }
}

struct PublicVideoPoster: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    let file: Record
    let ratio: CGFloat
    @State private var image: UIImage?
    @State private var failed = false
    @State private var evidence = "loading"
    var body: some View {
        ZStack {
            PUBOTheme.button
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                VStack(spacing: 6) {
                    Image(systemName: "video").font(.title2)
                    Text(failed ? "视频预览暂不可用" : "正在加载视频画面…").font(.caption)
                }.foregroundStyle(PUBOTheme.text)
            }
        }.aspectRatio(ratio, contentMode: .fit)
            .accessibilityIdentifier("media.poster." + file.id)
            .accessibilityValue(evidence)
            .task(id: file.id + (file["url"].string ?? "") + (file["thumbnailUrl"].string ?? "") + String(describing: session.generation) + String(describing: phase)) {
                guard phase == .active else { return }; await load()
            }.onDisappear { image = nil }
    }
    @MainActor private func load() async {
        PublicMediaDiagnostics.emit(.posterStarted)
        image = nil; failed = false; evidence = "loading"
        let epoch = session.generation
        let key = PublicPreviewCache.shared.key("video:" + (file["url"].string ?? file.id) + ":" + (file["thumbnailUrl"].string ?? ""), generation: String(describing: epoch))
        if let cached = PublicPreviewCache.shared.image(key) { image = cached; evidence = "cached"; PublicMediaDiagnostics.emit(.posterCached); return }
        // Prefer the server poster: no video decoding or video transfer is needed.
        if let thumb = safeMediaURL(file["thumbnailUrl"].string) {
            PublicMediaDiagnostics.emit(.thumbnailStarted)
            do {
                let bytes: Data
                #if DEBUG
                if session.testMode && !session.isolatedBackend {
                    guard let fixture = TimelineTestFixtures.media(thumb) else { throw APIError.invalidResponse }; bytes = fixture
                } else { bytes = try await PublicImageDecoder.data(thumb, limit: 8 * 1024 * 1024) }
                #else
                bytes = try await PublicImageDecoder.data(thumb, limit: 8 * 1024 * 1024)
                #endif
                let decoded = try await PublicImageDecoder.decode(bytes, maxPixel: 720)
                try Task.checkCancellation()
                guard epoch == session.generation else { return }
                image = decoded; evidence = "thumbnail"; PublicMediaDiagnostics.emit(.thumbnailReady); PublicPreviewCache.shared.insert(decoded, key: key); return
            } catch {
                if Task.isCancelled { PublicMediaDiagnostics.emit(.cancelled); return }
                PublicMediaDiagnostics.emit(.thumbnailFailed)
            }
        }
        var videoSource = safeMediaURL(file["url"].string)
        #if DEBUG
        // Synthetic UI mode only decodes this explicitly opted-in bundled asset.
        // Unknown fixture URLs fail closed; never fall back to the network.
        if session.testMode && !session.isolatedBackend {
            videoSource = TimelineTestFixtures.videoSource(videoSource)
        }
        #endif
        guard let source = videoSource else { failed = true; evidence = "unavailable"; PublicMediaDiagnostics.emit(.sourceUnavailable); return }
        do {
            PublicMediaDiagnostics.emit(.budgetWaiting)
            try await VideoPosterBudget.shared.acquire()
            PublicMediaDiagnostics.emit(.budgetAcquired)
            do {
                PublicMediaDiagnostics.emit(.generatorStarted)
                let asset = AVURLAsset(url: source)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 720, height: 720)
                let deadline = Task { try await Task.sleep(for: .seconds(8)); generator.cancelAllCGImageGeneration() }
                defer { deadline.cancel() }
                let result = try await withTaskCancellationHandler {
                    try await generator.image(at: .zero)
                } onCancel: { generator.cancelAllCGImageGeneration() }
                try Task.checkCancellation()
                if epoch == session.generation {
                    let decoded = UIImage(cgImage: result.image)
                    image = decoded; evidence = "video-frame"; PublicMediaDiagnostics.emit(.generatorReady); PublicPreviewCache.shared.insert(decoded, key: key)
                }
            } catch {
                if !Task.isCancelled && epoch == session.generation {
                    failed = true; evidence = "unavailable"
                    PublicMediaDiagnostics.emit(.generatorFailed)
                } else { PublicMediaDiagnostics.emit(.cancelled) }
            }
            await VideoPosterBudget.shared.release()
        } catch { /* View disappeared while waiting for a decoder. */ }
    }
}
