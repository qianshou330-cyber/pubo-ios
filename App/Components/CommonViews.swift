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
        AsyncImage(url: safeMediaURL(user["avatarUrl"].string)) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
            .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

func safeMediaURL(_ text: String?) -> URL? {
    guard let text, let url = URL(string: text), url.scheme == "https", url.user == nil, url.password == nil else { return nil }
    return url
}

@Observable @MainActor final class InlineEmojiStore {
    static let shared = InlineEmojiStore()
    private(set) var images: [String: UIImage] = [:]
    private var inFlight = Set<String>()
    private var generation = UUID()
    func clear() { generation = UUID(); images.removeAll() }
    func load(_ urls: [String: URL]) async {
        let epoch = generation
        for (name, url) in urls where images[name] == nil && !inFlight.contains(name) {
            inFlight.insert(name)
            defer { inFlight.remove(name) }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard epoch == generation, !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000, let image = UIImage(data: data) else { continue }
                let rendered = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 20, height: 20)) }
                if images.count > 256 { images.removeAll() }
                images[name] = rendered
            } catch { }
        }
    }
}

struct NoteText: View {
    @Environment(AppSession.self) private var session
    let text: String
    var remoteEmojis: JSONValue = .null
    var expands = true
    @State private var emojiStore = InlineEmojiStore.shared
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
    private var rendered: Text {
        parts.reduce(Text("")) { output, part in
            if let key = urls.keys.first(where: { $0.hasPrefix(part + "https://") }), let image = emojiStore.images[key] { return output + Text(Image(uiImage: image)).baselineOffset(-3) }
            return output + Text(part)
        }
    }
    var body: some View {
        rendered.textSelection(.enabled).frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            .task(id: urls.keys.sorted().joined()) { await emojiStore.load(urls) }
    }
}

struct PublicMedia: View {
    let file: Record
    let noteID: String
    @State private var playing = false
    var body: some View {
        Group {
            if file["isSensitive"].bool {
                VStack(spacing: 8) { Label("敏感媒体不在 App 内显示", systemImage: "eye.slash"); Link("在网页查看原帖", destination: Endpoint.origin.appendingPathComponent("notes/" + noteID)) }.font(.callout).frame(maxWidth: .infinity, minHeight: 100).background(PUBOTheme.button)
            } else if let url = safeMediaURL(file["url"].string) {
                if file["type"].string?.hasPrefix("image/") == true {
                    AsyncImage(url: safeMediaURL(file["thumbnailUrl"].string) ?? url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView().frame(height: 100) }
                        .frame(maxHeight: 340).accessibilityLabel(file["comment"].string ?? "帖子图片")
                } else if file["type"].string?.hasPrefix("video/") == true || file["type"].string?.hasPrefix("audio/") == true {
                    Button { playing = true } label: { Label("播放媒体", systemImage: "play.circle.fill").frame(maxWidth: .infinity, minHeight: 100) }.sheet(isPresented: $playing) { MediaPlayer(url: url) }
                } else { Link(file["name"].string ?? "打开附件", destination: url) }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MediaPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player).onAppear { player = AVPlayer(url: url); player?.play() }.onDisappear { player?.pause(); player = nil }
    }
}

struct ReactionPicker: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let choose: (String) -> Void
    @State private var search = ""
    private var available: [JSONValue] {
        let roles = Set(session.user?["roles"].array.compactMap { $0["id"].string } ?? [])
        return session.emojis.filter {
            let allowed = Set($0["roleIdsThatCanBeUsedThisEmojiAsReaction"].array.compactMap(\.string))
            return !$0["isSensitive"].bool && (allowed.isEmpty || !roles.isDisjoint(with: allowed)) && (search.isEmpty || ($0["name"].string ?? "").localizedCaseInsensitiveContains(search) || $0["aliases"].array.contains { ($0.string ?? "").localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 55))], spacing: 18) {
                    ForEach(["❤️", "👍", "🔥", "🎉", "🥰", "👏", "😂", "😮"], id: \.self) { emoji in Button(emoji) { choose(emoji); dismiss() }.font(.title) }
                    ForEach(available, id: \.selfID) { emoji in
                        if let name = emoji["name"].string {
                            Button { choose(":" + name + ":"); dismiss() } label: {
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
