import SwiftUI
import PUBOCore

/// Chat uses the same selectable TextKit/animated-emoji renderer as notes, without
/// relying on a "note." accessibility-ID prefix to select the rich code path.
struct ChatMessageContent: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let active: Bool
    let identifier: String
    var remoteEmojis: JSONValue = .null
    @State private var visible = false
    @State private var emojiStore = InlineEmojiStore.shared
    @State private var destination: NativeLinkTarget?
    private var parts: [String] { ChatContentPolicy.emojiParts(text) }
    private var urls: [String: URL] {
        var result: [String: URL] = [:]
        for part in parts where part.hasPrefix(":") && part.hasSuffix(":") {
            let name = String(part.dropFirst().dropLast())
            let value = remoteEmojis[name].string ?? session.emojis.first(where: { $0["name"].string == name })?["url"].string
            if let url = safeMediaURL(value) { result[part + url.absoluteString] = url }
        }
        return result
    }
    private var enabled: Bool { active && visible && phase == .active }
    var body: some View {
        RichNoteText(parts: parts, urls: urls, images: emojiStore.images,
                     playing: enabled && !reduceMotion, identifier: identifier,
                     openURL: { url in
                         if let link = NativeLink(url) { destination = NativeLinkTarget(link: link) }
                         else if NativeLink.publicURL(url.absoluteString) != nil { UIApplication.shared.open(url) }
                     }, fitsContentWidth: true)
            .background(GeometryReader { geometry in
                Color.clear.onAppear { visible = geometry.frame(in: .global).intersects(UIScreen.main.bounds) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in visible = frame.intersects(UIScreen.main.bounds) }
            })
            .task(id: "\(session.generation)-\(enabled)-" + urls.keys.sorted().joined(separator: "|")) {
                guard enabled else { return }
                await emojiStore.load(urls)
            }
            .onDisappear { visible = false }
            .sheet(item: $destination) { NativeLinkDestination(target: $0.link) }
    }
}

/// H5 places these cards outside the message bubble, above time/actions.
struct ChatMessageLinkPreviews: View {
    let text: String
    let active: Bool
    let identifier: String
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(ChatContentPolicy.previewLinks(text).enumerated()), id: \.element.absoluteString) { index, url in
                ChatLinkPreviewCard(url: url, active: active, identifier: identifier + ".\(index)")
            }
        }
    }
}

private struct ChatLinkPreviewCard: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    let url: URL
    let active: Bool
    let identifier: String
    @State private var visible = false
    @State private var metadata: JSONValue?
    @State private var failed = false
    @State private var loading = false
    @State private var retry = 0
    @State private var owner: UUID?
    @State private var destination: NativeLinkTarget?
    private var enabled: Bool { active && visible && phase == .active }
    private var current: JSONValue? { owner == session.generation ? metadata : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                // Metadata never replaces the message's original, validated destination.
                if let link = NativeLink(url) { destination = NativeLinkTarget(link: link) }
                else { UIApplication.shared.open(url) }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    if let current, !current["sensitive"].bool,
                       let thumbnail = current["thumbnail"].string,
                       let imageURL = ChatContentPolicy.previewURL(thumbnail), imageURL.scheme == "https" {
                        ChatPreviewThumbnail(url: imageURL, active: enabled)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current?["title"].string ?? url.absoluteString).font(.caption.bold()).lineLimit(2)
                        if let summary = current?["description"].string, !summary.isEmpty {
                            Text(summary).font(.caption2).lineLimit(3)
                        } else if failed { Text("暂时无法预览，仍可打开原链接").font(.caption2) }
                        else if loading { Text("正在加载链接预览…").font(.caption2) }
                        Text(current?["sitename"].string ?? url.host ?? "网页").font(.caption2).foregroundStyle(PUBOTheme.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 44).padding(8).foregroundStyle(PUBOTheme.text)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            if failed {
                Button("重试链接预览") { retry += 1 }.font(.caption).frame(minHeight: 44)
                    .accessibilityIdentifier(identifier + ".retry")
            }
        }.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PUBOTheme.divider))
            .background(GeometryReader { geometry in
                Color.clear.onAppear { visible = geometry.frame(in: .global).intersects(UIScreen.main.bounds) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in visible = frame.intersects(UIScreen.main.bounds) }
            })
            .task(id: "\(session.generation)-\(enabled)-\(retry)-\(url.absoluteString)") {
                let epoch = session.generation
                if owner != epoch { metadata = nil; failed = false; owner = epoch }
                guard enabled, metadata == nil else { return }
                loading = true
                defer { loading = false }
                do {
                    let value = try await fetch()
                    guard !Task.isCancelled, epoch == session.generation else { return }
                    metadata = value; failed = false
                } catch {
                    guard !Task.isCancelled, epoch == session.generation else { return }
                    failed = true
                }
            }
            .onDisappear { visible = false }
            .sheet(item: $destination) { NativeLinkDestination(target: $0.link) }
    }
    private func fetch() async throws -> JSONValue {
        #if DEBUG
        if session.testMode && !session.isolatedBackend {
            if ProcessInfo.processInfo.arguments.contains("--chat-preview-failure"), retry == 0 { throw APIError.invalidResponse }
            return .object(["title": .string("PUBO 合成链接预览"), "description": .string("这是隔离测试中的链接摘要，不访问生产网页。"), "sitename": .string(url.host ?? "网页")])
        }
        #endif
        var endpoint = URLComponents(url: Endpoint.origin.appendingPathComponent("url"), resolvingAgainstBaseURL: false)!
        endpoint.queryItems = [.init(name: "url", value: url.absoluteString), .init(name: "lang", value: "zh-CN")]
        let result = try JSONDecoder().decode(JSONValue.self, from: await PublicImageDecoder.data(endpoint.url!, limit: 512_000))
        guard result["title"].string != nil || result["description"].string != nil else { throw APIError.invalidResponse }
        return result
    }
}

private struct ChatPreviewThumbnail: View {
    @Environment(AppSession.self) private var session
    let url: URL
    let active: Bool
    @State private var image: UIImage?
    @State private var owner: UUID?
    var body: some View {
        Group {
            if owner == session.generation, let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "link").foregroundStyle(PUBOTheme.secondary) }
        }.frame(width: 62, height: 62).clipped().accessibilityHidden(true)
            .task(id: "\(session.generation)-\(active)-\(url.absoluteString)") {
                let epoch = session.generation
                if owner != epoch { image = nil; owner = epoch }
                guard active, image == nil else { return }
                do {
                    let data: Data
                    #if DEBUG
                    if session.testMode && !session.isolatedBackend {
                        guard let fixture = TimelineTestFixtures.media(url) else { return }; data = fixture
                    } else { data = try await PublicImageDecoder.data(url, limit: 2_000_000) }
                    #else
                    data = try await PublicImageDecoder.data(url, limit: 2_000_000)
                    #endif
                    let decoded = try await PublicImageDecoder.decode(data, maxPixel: 240)
                    guard !Task.isCancelled, epoch == session.generation else { return }
                    image = decoded
                } catch { /* Keep the accessible text card when artwork is unavailable. */ }
            }
    }
}
