/// A plain-text subtitle for an already-loaded followee; not an identity or URL parser.
public enum FolloweeDisplayHandle {
    private static let localSystemUsernames: Set<String> = ["system.actor", "system.relay", "system.proxy"]

    public static func text(for user: Record) -> String? {
        let fields = user.raw.object
        // Record's subscript collapses missing into .null; the latter alone means local.
        guard let username = fields["username"]?.string, !username.isEmpty,
              let host = fields["host"] else { return nil }
        let name = username.utf8
        switch host {
        case .null:
            guard (name.count <= 20 && name.allSatisfy(isWord)) || localSystemUsernames.contains(username) else { return nil }
            return "@\(username)"
        case .string(let remote):
            // Archived actor grammar: /^\w([\w-.]*\w)?$/ with at most 128 ASCII bytes.
            guard name.count <= 128, let first = name.first, let last = name.last,
                  isWord(first), isWord(last), name.allSatisfy({ isWord($0) || $0 == 45 || $0 == 46 }),
                  isRemoteHost(remote) else { return nil }
            return "@\(username)@\(remote)"
        default:
            return nil
        }
    }

    private static func isRemoteHost(_ value: String) -> Bool {
        guard value.utf8.count <= 259 else { return false } // 253-byte name plus a colon and five port digits.
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let domain = parts.first, !domain.isEmpty, domain.utf8.count <= 253 else { return false }
        if parts.count == 2 {
            let port = parts[1]
            guard (1...5).contains(port.utf8.count), port.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = UInt16(port), number > 0 else { return false }
        }
        // ASCII DNS label spelling, including punycode A-labels as supplied. No normalization or lookup.
        return domain.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            let bytes = label.utf8
            guard (1...63).contains(bytes.count), let first = bytes.first, let last = bytes.last,
                  isASCIILetterOrDigit(first), isASCIILetterOrDigit(last) else { return false }
            return bytes.allSatisfy { isASCIILetterOrDigit($0) || $0 == 45 }
        }
    }

    private static func isWord(_ byte: UInt8) -> Bool { isASCIILetterOrDigit(byte) || byte == 95 }

    private static func isASCIILetterOrDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...90, 97...122: return true
        default: return false
        }
    }
}
