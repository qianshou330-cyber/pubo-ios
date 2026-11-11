import Foundation

/// Privacy constraints shared by draft restoration, the picker and the request.
/// A restored draft may be narrower than the reply; never widen it implicitly.
public enum ComposePrivacy {
    public struct Selection: Equatable, Sendable {
        public let visibility: String
        public let localOnly: Bool
        public let recipientIDs: [String]
    }
    private static let order = ["public", "home", "followers", "specified"]

    public static func allowedVisibilities(reply: Record?, channelID: String?, silenced: Bool = false) -> [String] {
        if channelID != nil { return ["public"] }
        let floor = max(silenced ? 1 : 0, order.firstIndex(of: reply?["visibility"].string ?? "public") ?? 0)
        return Array(order[floor...])
    }

    public static func replyRecipientIDs(_ reply: Record?, accountID: String) -> [String] {
        guard let reply, reply["visibility"].string == "specified" else { return [] }
        let author = reply["userId"].string ?? reply.user.id
        return unique(reply["visibleUserIds"].array.compactMap(\.string) + [author]).filter { $0 != accountID }
    }

    public static func resolve(visibility: String, localOnly: Bool, recipientIDs: [String],
                               reply: Record?, channelID: String?, accountID: String,
                               seedReplyRecipients: Bool = false, silenced: Bool = false) -> Selection {
        if channelID != nil { return Selection(visibility: "public", localOnly: true, recipientIDs: []) }
        let allowed = allowedVisibilities(reply: reply, channelID: nil, silenced: silenced)
        let chosen = allowed.contains(visibility) ? visibility : (allowed.first ?? "specified")
        var recipients = unique(recipientIDs)
        if reply?["visibility"].string == "specified" {
            let permitted = replyRecipientIDs(reply, accountID: accountID)
            // Seed a new reply, or repair a legacy public draft. Do not restore
            // recipients deliberately removed from an existing specified draft.
            if seedReplyRecipients || visibility != "specified" { recipients = permitted }
            else { recipients = recipients.filter { permitted.contains($0) } }
        }
        return Selection(visibility: chosen, localOnly: chosen == "specified" ? false : localOnly,
                         recipientIDs: chosen == "specified" ? recipients : [])
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
