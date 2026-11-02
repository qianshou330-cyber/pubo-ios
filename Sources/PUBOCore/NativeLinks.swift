import Foundation

public enum NativeLink: Equatable, Sendable {
    case note(String), user(String), handle(String, String?), tag(String)
    public init?(_ url: URL) {
        guard url.scheme == "https", url.host?.lowercased() == "bolubo.com", url.port == nil || url.port == 443, url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count == 2, parts[0] == "notes", Self.identifier(parts[1]) { self = .note(parts[1]) }
        else if parts.count == 2, parts[0] == "users", Self.identifier(parts[1]) { self = .user(parts[1]) }
        else if parts.count == 2, parts[0] == "tags", !parts[1].isEmpty { self = .tag(parts[1]) }
        else if parts.count == 1, parts[0].hasPrefix("@") {
            let handle = parts[0].dropFirst().split(separator: "@", omittingEmptySubsequences: false).map(String.init)
            guard handle.count == 1 || handle.count == 2, handle[0].range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else { return nil }
            let host = handle.count == 2 ? handle[1] : nil
            guard host == nil || host?.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { return nil }
            self = .handle(handle[0], host)
        } else { return nil }
    }
    public static func identifier(_ string: String) -> Bool { string.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil }
    public static func publicURL(_ string: String) -> URL? {
        guard let url = URL(string: string), ["https", "http"].contains(url.scheme), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func linkedText(_ text: String) -> String {
        // Do not rewrite Markdown/code fragments: keep their existing syntax intact.
        let pattern = #"(```[\s\S]*?```|`[^`\n]*`|\[[^\]\n]+\]\([^\s)]+\)|https?://[^\s<>]+)|(?<![\w@/])(@[A-Za-z0-9_]+(?:@[A-Za-z0-9.-]+)?|#[\p{L}\p{N}_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let value = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            if match.range(at: 2).location == NSNotFound {
                let token = (text as NSString).substring(with: match.range)
                if publicURL(token) != nil { value.replaceCharacters(in: match.range, with: "<\(token)>") }
                continue
            }
            let token = (text as NSString).substring(with: match.range(at: 2))
            var url = URLComponents(string: "https://bolubo.com")!
            url.path = token.hasPrefix("#") ? "/tags/" + token.dropFirst() : "/" + token
            if let address = url.url { value.replaceCharacters(in: match.range(at: 2), with: "[\(token)](\(address.absoluteString))") }
        }
        return value as String
    }
}
