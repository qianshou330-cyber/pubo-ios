import SwiftUI
import AVFoundation
import ImageIO
import PUBOCore

struct ChatBottomPreference: PreferenceKey {
    static var defaultValue: CGFloat { .greatestFiniteMagnitude }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ChatReactionStrip: View {
    let reactions: [JSONValue]
    let ownUserID: String
    var enabled = true
    let toggle: (String) -> Void
    private var keys: [String] { Array(Set(reactions.compactMap { $0["reaction"].string })).sorted() }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    let matches = reactions.filter { $0["reaction"].string == key }
                    let mine = matches.contains { $0["user"]["id"].string == ownUserID || $0["userId"].string == ownUserID }
                    Button { toggle(key) } label: {
                        HStack(spacing: 4) { NoteText(text: key, expands: false); Text("\(matches.count)").font(.caption) }
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(mine ? PUBOTheme.accent.opacity(0.16) : PUBOTheme.button, in: Capsule())
                            .overlay(Capsule().stroke(mine ? PUBOTheme.accent : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel((mine ? "取消反应 " : "添加反应 ") + key)
                }
            }
        }.scrollIndicators(.hidden)
    }
}

/// Uses the existing authenticated attachment request; no public URLs or shared disk cache.
struct PrivateInlineAttachment: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let attachment: Record
    let open: () -> Void
    @State private var image: UIImage?
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var loading = false
    @State private var error: String?
    @State private var active = false
    private var voice: Bool { attachment["kind"].string == "voice" }
    private var picture: Bool { (attachment["mime"].string ?? "").hasPrefix("image/") }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if picture, let image {
                Button(action: open) { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel("查看私信图片")
            } else if voice {
                Button { Task { await play() } } label: { Label(playing ? "暂停语音" : "播放语音", systemImage: playing ? "pause.fill" : "waveform").frame(minWidth: 130, minHeight: 44) }.disabled(loading)
                Button("查看与保存语音", action: open).font(.caption).frame(minHeight: 44)
            } else {
                Button(action: open) { Label(attachment["name"].string ?? "附件", systemImage: picture ? "photo" : "paperclip").lineLimit(2).frame(minHeight: 44) }
            }
            if loading { ProgressView("验证附件权限…").font(.caption) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary); if picture { Button("重试图片") { Task { await loadImage() } } } }
        }.task { active = true; if picture { await loadImage() } }
            .onDisappear { active = false; clear() }
            .onChange(of: session.generation) { _, _ in active = false; clear() }
            .onChange(of: session.activeVoiceAttachmentID) { _, id in if id != attachment.id { player?.pause(); playing = false } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause(); playing = false; image = nil } else if picture { Task { await loadImage() } } }
            .task(id: playing) { if playing { try? await Task.sleep(for: .milliseconds(250)); while playing && !Task.isCancelled { if player?.isPlaying != true { playing = false }; try? await Task.sleep(for: .milliseconds(250)) } } }
    }
    private func content() async throws -> Data {
        guard active, scenePhase == .active, attachment["size"].int <= 50 * 1024 * 1024, let token = session.token else { throw APIError.invalidResponse }
        return try await session.api.privateAttachment(id: attachment.id, token: token)
    }
    private func loadImage() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        let owner = session.generation
        do {
            let data = try await content(); guard active, owner == session.generation, scenePhase == .active, !Task.isCancelled else { return }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 720] as CFDictionary) else { throw APIError.invalidResponse }
            image = UIImage(cgImage: decoded); error = nil
        }
        catch { if active && owner == session.generation && !Task.isCancelled { self.error = "图片暂不可用，点击重试。" } }
    }
    private func play() async {
        guard !loading else { return }
        if playing { player?.pause(); playing = false; return }
        loading = true; defer { loading = false }; let owner = session.generation
        do {
            // Reauthorize each play, including resuming after a pause or returning to the foreground.
            let data = try await content(); guard active, owner == session.generation, scenePhase == .active, !Task.isCancelled else { return }
            let position = player?.currentTime ?? 0
            session.activeVoiceAttachmentID = attachment.id
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(data: data); audio.currentTime = position < audio.duration ? position : 0; audio.prepareToPlay(); player = audio
            playing = audio.play(); error = playing ? nil : "语音暂时无法播放。"
        } catch { if active && owner == session.generation { self.error = "语音不可用或权限已变化，请重试。" } }
    }
    private func clear() { player?.stop(); player = nil; image = nil; playing = false }
}
