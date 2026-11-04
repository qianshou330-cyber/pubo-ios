import SwiftUI
import PUBOCore
import AVKit

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.circle").font(.callout)
            if let retry { Button("重试", action: retry) }
        }.foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, alignment: .leading).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: PUBOTheme.radius))
    }
}

struct Avatar: View {
    let user: Record
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            #if DEBUG
            if let url = safeMediaURL(user["avatarUrl"].string), url.host == "timeline-fixture.invalid" {
                PublicAnimatedAsset(url: url).frame(width: size, height: size).clipShape(Circle())
            } else {
                avatarImage
            }
            #else
            avatarImage
            #endif
            decorations
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    private var avatarImage: some View {
            AsyncImage(url: safeMediaURL(user["avatarUrl"].string)) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
                .frame(width: size, height: size).clipShape(Circle())
    }
    private var decorations: some View {
            ForEach(Array(user["avatarDecorations"].array.prefix(16).enumerated()), id: \.offset) { _, decoration in
                if let url = safeMediaURL(decoration["url"].string) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: size * 1.5, height: size * 1.5)
                        .scaleEffect(x: decoration["flipH"].bool ? -1 : 1, y: 1)
                        .rotationEffect(.degrees(number(decoration["angle"]) * 360))
                        .offset(x: size * number(decoration["offsetX"]), y: size * number(decoration["offsetY"]))
                }
            }
    }
    private func number(_ value: JSONValue) -> Double { if case .number(let number) = value, number.isFinite { return max(-1, min(1, number)) }; return 0 }
}

struct RoleBadges: View {
    let user: Record
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Record.list(user["badgeRoles"])) { role in
                    HStack(spacing: 4) {
                        if let url = safeMediaURL(role["iconUrl"].string) { AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(width: 18, height: 18) }
                        Text(role["name"].string ?? "角色")
                    }.font(.caption).padding(5).background(PUBOTheme.button, in: Capsule())
                }
            }
        }.scrollIndicators(.hidden)
    }
}

func safeMediaURL(_ text: String?) -> URL? {
    guard let text, let url = (text.hasPrefix("/") && !text.hasPrefix("//") ? URL(string: text, relativeTo: Endpoint.origin)?.absoluteURL : URL(string: text)), url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
    return url
}

@Observable @MainActor final class InlineEmojiStore {
    static let shared = InlineEmojiStore()
    private(set) var images: [String: UIImage] = [:]
    private var inFlight = Set<String>()
    private var generation = UUID()
    private var encodedBytes = 0
    func clear() { generation = UUID(); images.removeAll(); encodedBytes = 0; inFlight = [] }
    func load(_ urls: [String: URL]) async {
        let epoch = generation
        for (name, url) in urls where images[name] == nil && !inFlight.contains(name) {
            inFlight.insert(name)
            defer { inFlight.remove(name) }
            do {
                let data: Data
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { guard let fixture = TimelineTestFixtures.media(url) else { continue }; data = fixture }
                else { data = try await PublicImageDecoder.data(url, limit: 2_000_000) }
                #else
                data = try await PublicImageDecoder.data(url, limit: 2_000_000)
                #endif
                let rendered = try await PublicImageDecoder.decode(data, maxPixel: 100)
                guard epoch == generation, !Task.isCancelled else { return }
                if images.count >= 128 || encodedBytes + data.count > 32 * 1024 * 1024 { images.removeAll(); encodedBytes = 0 }
                encodedBytes += data.count
                images[name] = rendered
            } catch { }
        }
    }
}

struct NoteText: View {
    @Environment(AppSession.self) private var session
    let text: String
    var remoteEmojis: JSONValue = .null
    var onTap: (() -> Void)? = nil
    var identifier = ""
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    var expands = true
    @State private var emojiStore = InlineEmojiStore.shared
    @State private var destination: NativeLinkTarget?
    private var parts: [String] {
        let pattern = try! NSRegularExpression(pattern: ":[a-zA-Z0-9_]+:")
        let ns = text as NSString
        var cursor = 0; var result: [String] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor { result.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))) }
            result.append(ns.substring(with: match.range)); cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { result.append(ns.substring(from: cursor)) }
        return result
    }
    private var urls: [String: URL] {
        var map: [String: URL] = [:]
        for part in parts where part.hasPrefix(":") && part.hasSuffix(":") {
            let name = String(part.dropFirst().dropLast())
            let value = remoteEmojis[name].string ?? session.emojis.first(where: { $0["name"].string == name })?["url"].string
            if let url = safeMediaURL(value) { map[part + url.absoluteString] = url }
        }
        return map
    }
    private var legacyText: Text {
        parts.reduce(Text("")) { output, part in
            if let key = urls.keys.first(where: { $0.hasPrefix(part + "https://") }), let image = emojiStore.images[key] {
                let size = CGSize(width: 20 * min(4, max(0.25, image.size.width / max(1, image.size.height))), height: 20)
                let still = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                return output + Text(Image(uiImage: still)).baselineOffset(-3)
            }
            return output + Text((try? AttributedString(markdown: NativeLink.linkedText(part), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(part))
        }
    }
    var body: some View {
        Group {
        if identifier.hasPrefix("note.") {
        RichNoteText(parts: parts, urls: urls, images: emojiStore.images, playing: visible && phase == .active, identifier: identifier, openURL: { url in
            if let link = NativeLink(url) { destination = NativeLinkTarget(link: link) }
            else if NativeLink.publicURL(url.absoluteString) != nil { UIApplication.shared.open(url) }
        }, onTap: onTap)
        } else { legacyText.textSelection(.enabled).environment(\.openURL, OpenURLAction { url in
            if let link = NativeLink(url) { destination = NativeLinkTarget(link: link); return .handled }
            return NativeLink.publicURL(url.absoluteString) == nil ? .discarded : .systemAction
        }) }
        }.frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            .background(GeometryReader { g in Color.clear.onAppear { visible = g.frame(in: .global).intersects(UIScreen.main.bounds) }.onChange(of: g.frame(in: .global)) { _, rect in visible = rect.intersects(UIScreen.main.bounds) } })
            .task(id: urls.keys.sorted().joined()) { await emojiStore.load(urls) }
            .onDisappear { visible = false }
            .sheet(item: $destination) { NativeLinkDestination(target: $0.link) }
    }
}

struct PublicMedia: View {
    let file: Record
    let noteID: String
    var sourceURL: URL? = nil
    var body: some View { TimelineMediaItem(file: file, noteID: noteID) }
}

struct MediaPlayer: View {
    let url: URL
    @Environment(\.scenePhase) private var phase
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player).onAppear { player = AVPlayer(url: url); player?.play() }.onDisappear { player?.pause(); player = nil }.onChange(of: phase) { _, value in if value != .active { player?.pause() } }
    }
}

struct ReactionPicker: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let choose: (String) -> Void
    @State private var search = ""
    @State private var category = "全部"
    private var categories: [String] { ["全部", "常用"] + Array(Set(session.emojis.map { $0["category"].string ?? "未分类" })).sorted() }
    private var available: [JSONValue] {
        let roles = Set(session.user?["roles"].array.compactMap { $0["id"].string } ?? [])
        return session.emojis.filter {
            let allowed = Set($0["roleIdsThatCanBeUsedThisEmojiAsReaction"].array.compactMap(\.string))
            let named = ":" + ($0["name"].string ?? "") + ":"
            let matchesCategory = category == "全部" || (category == "常用" ? session.recentEmojis.contains(named) : ($0["category"].string ?? "未分类") == category)
            return matchesCategory && !$0["isSensitive"].bool && (allowed.isEmpty || !roles.isDisjoint(with: allowed)) && (search.isEmpty || ($0["name"].string ?? "").localizedCaseInsensitiveContains(search) || $0["aliases"].array.contains { ($0.string ?? "").localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("表情分类", selection: $category) { ForEach(categories, id: \.self) { Text($0).tag($0) } }.padding(.horizontal)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 55))], spacing: 18) {
                    ForEach((category == "常用" ? session.recentEmojis.filter { !$0.hasPrefix(":") } : category == "全部" ? ["❤️", "👍", "🔥", "🎉", "🥰", "👏", "😂", "😮"] : []), id: \.self) { emoji in Button(emoji) { session.rememberEmoji(emoji); choose(emoji); dismiss() }.font(.title) }
                    ForEach(available, id: \.selfID) { emoji in
                        if let name = emoji["name"].string {
                            Button { session.rememberEmoji(":" + name + ":"); choose(":" + name + ":"); dismiss() } label: {
                                AsyncImage(url: safeMediaURL(emoji["url"].string)) { image in image.resizable().scaledToFit() } placeholder: { Text(":" + name + ":").font(.caption2) }.frame(width: 40, height: 40)
                            }.accessibilityLabel(name)
                        }
                    }
                }.padding()
            }.puboScreen().searchable(text: $search, prompt: "搜索表情").navigationTitle("选择表情").toolbar { Button("关闭") { dismiss() } }
        }
    }
}

extension JSONValue { var selfID: String { self["id"].string ?? self["name"].string ?? "unknown" } }

/// Server dates can include fractional seconds. Missing dates stay absent.
func puboDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
