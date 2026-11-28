import AVFoundation
import Observation

@Observable @MainActor final class VoiceRecorder {
    private(set) var recording = false
    var onAutoFinish: (@MainActor (Bool) -> Void)?
    private var recorder: AVAudioRecorder?
    private var delegateProxy: Delegate?
    private var url: URL?
    func start() async throws {
        let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard granted else { throw VoiceError.denied }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audio.setActive(true)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("pubo-voice-\(UUID().uuidString).m4a")
        do {
            let instance = try AVAudioRecorder(url: path, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            let proxy = Delegate { [weak self] successfully in
                Task { @MainActor [weak self] in
                    guard let self, self.recording else { return }
                    if let onAutoFinish = self.onAutoFinish {
                        onAutoFinish(successfully)
                    } else {
                        self.cancel()
                    }
                }
            }
            instance.delegate = proxy
            guard instance.record(forDuration: 60) else { throw VoiceError.unavailable }
            recorder = instance; delegateProxy = proxy; url = path; recording = true
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path.path)
        } catch {
            url = path; cancel(); throw error
        }
    }
    func finish() throws -> Data {
        recording = false
        recorder?.delegate = nil
        recorder?.stop()
        defer { cleanup() }
        guard let url else { throw VoiceError.unavailable }
        return try Data(contentsOf: url)
    }
    func cancel() {
        recording = false
        recorder?.delegate = nil
        recorder?.stop()
        cleanup()
    }
    private func cleanup() {
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil; recorder = nil; delegateProxy = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private final class Delegate: NSObject, AVAudioRecorderDelegate {
        private let finished: (Bool) -> Void
        init(_ finished: @escaping (Bool) -> Void) { self.finished = finished }
        func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
            finished(flag)
        }
    }
    enum VoiceError: LocalizedError {
        case denied, unavailable
        var errorDescription: String? { self == .denied ? "需要麦克风权限才能录制语音。" : "无法录制语音，请稍后重试。" }
    }
}
