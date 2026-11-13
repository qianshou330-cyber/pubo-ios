import Foundation

public enum ChatConnectionPhase: String, Sendable {
    case idle, connecting, connected, reconnecting
}

public enum ChatPresentationPreferences {
    /// H5 registry stores [scope, value] pairs. More specific matching scope
    /// wins; another server/account/device can never affect this user's UI.
    public static func senderName(in value: JSONValue, accountID: String, server: String = "bolubo.com") -> Bool? {
        var best: (rank: Int, value: Bool)?
        for entry in value.array {
            let pair = entry.array
            guard pair.count >= 2, case .object = pair[0], case .bool(let enabled) = pair[1] else { continue }
            let scope = pair[0]
            guard scope["device"].isNull else { continue }
            let host = scope["server"].string, account = scope["account"].string
            guard scope["server"].isNull || host == server,
                  scope["account"].isNull || (account == accountID && host == server) else { continue }
            let rank = account != nil ? 2 : (host != nil ? 1 : 0)
            if best == nil || rank > best!.rank { best = (rank, enabled) }
        }
        return best?.value
    }
}
