import Foundation

/// A bounded subset of H5's MFM URL extraction, not a full MFM parser.
public enum ChatContentPolicy {
    public static func emojiParts(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: ":[a-zA-Z0-9_]+:") else { return [text] }
        let source = text as NSString
        var parts: [String] = [], cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > cursor { parts.append(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))) }
            parts.append(source.substring(with: match.range)); cursor = NSMaxRange(match.range)
        }
        if cursor < source.length { parts.append(source.substring(from: cursor)) }
        return parts
    }

    public static func previewLinks(_ text: String, limit: Int = 3) -> [URL] {
        // Never preview code, silent links (?[…] in MFM), or literal local addresses.
        // Keep the first occurrence, deduplicating fragments as H5 does.
        let excluded = #"```[\s\S]*?```|`[^`\n]*`|\?\[[^\]\n]*\]\([^\s)]+\)"#
        let stripped = text.replacingOccurrences(of: excluded, with: "", options: .regularExpression)
        let pattern = #"https?://[^\s<>\[\]`\"\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern), limit > 0 else { return [] }
        var result: [URL] = [], seen = Set<String>()
        for match in regex.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) {
            let raw = (stripped as NSString).substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?，。；！？"))
            guard let url = previewURL(raw), var identity = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            identity.fragment = nil
            guard seen.insert(identity.string ?? raw).inserted else { continue }
            result.append(url)
            if result.count == limit { break }
        }
        return result
    }

    public static func previewURL(_ value: String) -> URL? {
        guard let url = NativeLink.publicURL(value), let host = url.host?.lowercased(), host.contains("."),
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
              !host.contains(":"), !host.hasPrefix("127."), !host.hasPrefix("10."),
              !host.hasPrefix("192.168."), !host.hasPrefix("169.254."), !host.hasPrefix("0.") else { return nil }
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) {
            if parts[0] == "172", let second = Int(parts[1]), (16...31).contains(second) { return nil }
            if let first = Int(parts[0]), first >= 224 { return nil }
        }
        return url
    }
}
