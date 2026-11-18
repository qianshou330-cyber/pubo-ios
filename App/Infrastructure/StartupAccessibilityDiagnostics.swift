import SwiftUI
#if DEBUG
import OSLog

/// Synthetic observation only. Does not supply geometry to UI tests or mutate UI.
@MainActor enum StartupAccessibilityDiagnostics {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
        ProcessInfo.processInfo.arguments.contains("--chat-load-fail-once") &&
        !ProcessInfo.processInfo.arguments.contains("--isolated-backend")
    private static let logger = Logger(subsystem: "com.pubo.startup.diagnostics", category: "main-layout")
    private static var emitted = 0
    private static var layoutEmitted = 0
    private static var samplingStarted = false
    enum Event: String { case sessionInitStart, sessionInitReturned, rootStart, rootReturned, sceneActive, sceneInactive, sceneBackground, barAppeared, barChanged, barDisappeared, pulseStart, pulse, pulseEnd }
    static func record(_ event: Event, frame: CGRect = .zero, interval: TimeInterval = 0, cancelled: Bool = false) {
        guard enabled, emitted < 128 else { return }
        let terminal = event == .rootReturned || event == .sessionInitReturned || event == .pulseEnd
        guard terminal || emitted < 124 else { return }
        if event == .barAppeared || event == .barChanged || event == .barDisappeared {
            guard layoutEmitted < 32 else { return }
            layoutEmitted += 1
        }
        emitted += 1
        let finite = [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
        let message = "event=\(event.rawValue) uptime=\(ProcessInfo.processInfo.systemUptime) pid=\(ProcessInfo.processInfo.processIdentifier) main=\(Thread.isMainThread) finite=\(finite) coordinate=global frame=\(frame) interval=\(interval) cancelled=\(cancelled)"
        logger.notice("\(message, privacy: .public)")
    }
    /// A bounded MainActor scheduling sample, not a readiness condition or wait.
    /// Sleep permits idling; actual gaps include scheduling/host delay, not only UI work.
    static func sampleMainScheduling() async {
        guard enabled, !samplingStarted else { return }
        samplingStarted = true
        record(.pulseStart)
        defer { record(.pulseEnd, cancelled: Task.isCancelled) }
        var previous = ProcessInfo.processInfo.systemUptime
        for _ in 0..<60 {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            let now = ProcessInfo.processInfo.systemUptime
            record(.pulse, interval: now - previous)
            previous = now
        }
    }
}
#endif

/// Background-only measurement of the BAR container, never a button/AX proxy.
struct StartupTabLayoutDiagnostics: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if StartupAccessibilityDiagnostics.enabled {
            content.background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear
                        .onAppear { StartupAccessibilityDiagnostics.record(.barAppeared, frame: frame) }
                        .onChange(of: frame) { _, value in StartupAccessibilityDiagnostics.record(.barChanged, frame: value) }
                        .onDisappear { StartupAccessibilityDiagnostics.record(.barDisappeared) }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        } else { content }
        #else
        content
        #endif
    }
}
