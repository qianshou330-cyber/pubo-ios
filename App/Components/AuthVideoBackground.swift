import SwiftUI
import AVFoundation

/// Bundled decorative media: no network, audio session, controls or background playback.
struct AuthVideoBackground: View {
    var active = true
    var paused = false
    var softened = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashing
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var staticOnly: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
            ProcessInfo.processInfo.arguments.contains(where: { ["--reduce-motion", "--low-power-preview", "--missing-video-preview"].contains($0) }) { return true }
        #endif
        return reduceMotion || dimFlashing || lowPower
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PUBOTheme.background
                if let path = Bundle.main.path(forResource: "login-background-poster", ofType: "jpg"), let poster = UIImage(contentsOfFile: path) {
                    Image(uiImage: poster).resizable().scaledToFill()
                }
                if active && !paused && !staticOnly && scenePhase == .active,
                   let url = Bundle.main.url(forResource: "login-background", withExtension: "mp4") {
                    AuthLoopingVideo(url: url)
                }
                // Preserve black-on-light / white-on-dark branding and input contrast.
                (colorScheme == .dark ? Color.black : Color.white)
                    .opacity(softened ? (colorScheme == .dark ? 0.76 : 0.88) : (colorScheme == .dark ? 0.35 : 0.72))
                LinearGradient(colors: [.clear, PUBOTheme.background.opacity(softened ? 0.18 : 0.70)], startPoint: .top, endPoint: .bottom)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().allowsHitTesting(false)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

private struct AuthLoopingVideo: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> AuthPlayerView { AuthPlayerView(url: url) }
    func updateUIView(_ view: AuthPlayerView, context: Context) {}
    static func dismantleUIView(_ view: AuthPlayerView, coordinator: ()) { view.stop() }
}

private final class AuthPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var readiness: NSKeyValueObservation?
    private var clock: Any?

    init(url: URL) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.player = player
        videoLayer.opacity = 0
        player.isMuted = true
        player.volume = 0
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        readiness = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            DispatchQueue.main.async { self?.videoLayer.opacity = ready ? 1 : 0 }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            isAccessibilityElement = true
            accessibilityIdentifier = "auth.videoPlayback"
            accessibilityLabel = "Background video diagnostics"
            clock = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self else { return }
                self.accessibilityValue = "\(self.looper?.loopCount ?? 0):\(Int(time.seconds * 1000))"
            }
        } else { isAccessibilityElement = false }
        #else
        isAccessibilityElement = false
        #endif
        player.play()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func stop() {
        readiness?.invalidate(); readiness = nil
        if let clock { player.removeTimeObserver(clock); self.clock = nil }
        player.pause(); looper?.disableLooping(); looper = nil
        player.removeAllItems(); videoLayer.player = nil
    }
}
