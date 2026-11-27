import Foundation

/// The existing H5 QR page encodes https://bolubo.com/users/<id>.
/// Scanning is a read-only lookup, never a login, payment or follow action.
public enum UserQRCode {
    private static let allowedIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    private static func isValidUserID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.unicodeScalars.allSatisfy { allowedIDCharacters.contains($0) }
    }

    public static func userID(from value: String) -> String? {
        guard value.count <= 512, value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URLComponents(string: value), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "bolubo.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.query == nil, url.fragment == nil else { return nil }
        let prefix = "/users/"
        guard url.percentEncodedPath.hasPrefix(prefix) else { return nil }
        let id = String(url.percentEncodedPath.dropFirst(prefix.count))
        guard isValidUserID(id) else { return nil }
        return id
    }

    /// Generates the canonical H5-compatible user QR URL (`https://bolubo.com/users/<id>`).
    public static func url(forUserID id: String) -> URL? {
        guard isValidUserID(id) else { return nil }
        let raw = "https://bolubo.com/users/\(id)"
        guard userID(from: raw) == id else { return nil }
        return URL(string: raw)
    }

    /// Formats the H5 QR card account handle (e.g. `@alice@bolubo.com`).
    public static func displayHandle(username: String?, host: String? = nil) -> String? {
        guard let rawName = username?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else { return nil }
        let cleanName = rawName.hasPrefix("@") ? String(rawName.dropFirst()) : rawName
        guard !cleanName.isEmpty else { return nil }
        let rawHost = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = (rawHost?.isEmpty == false ? rawHost! : "bolubo.com")
        return "@\(cleanName)@\(resolvedHost)"
    }
}
