import AVFoundation
import Observation

@Observable @MainActor final class VoiceRecorder {
    private(set) var recording = false
    private var recorder: AVAudioRecorder?
    private var url: URL?
    func start() async throws {
        let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard granted else { throw VoiceError.denied }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audio.setActive(true)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("pubo-voice-\(UUID().uuidString).m4a")
        let instance = try AVAudioRecorder(url: path, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
        guard instance.record(forDuration: 60) else { throw VoiceError.unavailable }
        recorder = instance; url = path; recording = true
        do { try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path.path) }
        catch { cancel(); throw error }
    }
    func finish() throws -> Data {
        recorder?.stop(); recording = false
        defer { cleanup() }
        guard let url else { throw VoiceError.unavailable }
        return try Data(contentsOf: url)
    }
    func cancel() { recorder?.stop(); recording = false; cleanup() }
    private func cleanup() {
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil; recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    enum VoiceError: LocalizedError {
        case denied, unavailable
        var errorDescription: String? { self == .denied ? "需要麦克风权限才能录制语音。" : "无法录制语音，请稍后重试。" }
    }
}
