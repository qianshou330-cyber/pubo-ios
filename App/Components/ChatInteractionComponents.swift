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
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var rows: [ChatReaction] { ChatReaction.rows(reactions) }
    var body: some View {
        ChatReactionFlow {
            ForEach(rows) { row in
                let mine = row.user.id == ownUserID
                Button {
                    if row.isActionable(viewer: ownUserID, all: rows) { toggle(row.emoji) }
                } label: {
                    HStack(spacing: 8) {
                        Avatar(user: row.user, size: 24)
                        NoteText(text: row.emoji, expands: false).frame(width: 24, height: 24).allowsHitTesting(false)
                    }.padding(8).frame(minHeight: 44)
                        .background(PUBOTheme.panel, in: Capsule())
                        .overlay(Capsule().stroke(mine ? PUBOTheme.accent : PUBOTheme.divider, lineWidth: 1))
                }.buttonStyle(.plain).disabled(!enabled)
                    .accessibilityLabel((mine ? "取消反应 " : "添加反应 ") + row.emoji)
                    .accessibilityValue(row.user.displayName)
                    .transition(reduced ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
            }
        }.animation(reduced ? nil : .timingCurve(0, 0.5, 0.5, 1, duration: 0.2), value: rows.map(\.id))
    }
}

/// Uses the existing authenticated attachment request; no public URLs or shared disk cache.
struct PrivateInlineAttachment: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let attachment: Record
    var mediaActive = true
    let open: () -> Void
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var loading = false
    @State private var error: String?
    @State private var active = false
    private var voice: Bool { attachment["kind"].string == "voice" }
    private var picture: Bool { (attachment["mime"].string ?? "").hasPrefix("image/") }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if picture {
                PrivateInlineImage(attachment: attachment, active: mediaActive, open: open)
            } else if voice {
                Button { Task { await play() } } label: { Label(playing ? "暂停语音" : "播放语音", systemImage: playing ? "pause.fill" : "waveform").frame(minWidth: 130, minHeight: 44) }.disabled(loading)
                Button("查看与保存语音", action: open).font(.caption).frame(minHeight: 44)
            } else {
                Button(action: open) { Label(attachment["name"].string ?? "附件", systemImage: picture ? "photo" : "paperclip").lineLimit(2).frame(minHeight: 44) }
            }
            if loading { ProgressView("验证附件权限…").font(.caption) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }.task { active = true }
            .onDisappear { active = false; clear() }
            .onChange(of: session.generation) { _, _ in active = false; clear() }
            .onChange(of: session.activeVoiceAttachmentID) { _, id in if id != attachment.id { player?.pause(); playing = false } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause(); playing = false } }
            .task(id: playing) { if playing { try? await Task.sleep(for: .milliseconds(250)); while playing && !Task.isCancelled { if player?.isPlaying != true { playing = false }; try? await Task.sleep(for: .milliseconds(250)) } } }
    }
    private func content() async throws -> Data {
        guard active, scenePhase == .active, attachment["size"].int <= 50 * 1024 * 1024, let token = session.token else { throw APIError.invalidResponse }
        return try await session.api.privateAttachment(id: attachment.id, token: token)
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
    private func clear() { player?.stop(); player = nil; playing = false }
}
