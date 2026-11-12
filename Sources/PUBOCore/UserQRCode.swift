import Foundation

/// The existing H5 QR page encodes https://bolubo.com/users/<id>.
/// Scanning is a read-only lookup, never a login, payment or follow action.
public enum UserQRCode {
    public static func userID(from value: String) -> String? {
        guard value.count <= 512, value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URLComponents(string: value), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "bolubo.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.query == nil, url.fragment == nil else { return nil }
        let prefix = "/users/"
        guard url.percentEncodedPath.hasPrefix(prefix) else { return nil }
        let id = String(url.percentEncodedPath.dropFirst(prefix.count))
        guard !id.isEmpty, id.count <= 128,
              id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0) }) else { return nil }
        return id
    }
}
