import Foundation

/// Stable identities, independent of labels, positions and the legacy tab indices.
public enum AppTab: String, CaseIterable, Sendable, Identifiable {
    case messages, friends, world, me
    public var id: String { rawValue }
    public var title: String {
        switch self { case .messages: return "消息"; case .friends: return "好友"; case .world: return "世界圈"; case .me: return "我的" }
    }
}

public enum AppRoute: Hashable, Sendable {
    case chat(userID: String), room(String), note(String), notifications, followRequests
    public var tab: AppTab {
        switch self {
        case .chat, .room: return .messages
        case .note: return .world
        case .followRequests: return .friends
        case .notifications: return .me
        }
    }
}

public enum AppNavigationPolicy {
    /// Account generation must match too: signing out and back in invalidates old work.
    public static func canRoute(owner: String, generation: UUID, currentOwner: String?, currentGeneration: UUID) -> Bool {
        !owner.isEmpty && owner == currentOwner && generation == currentGeneration
    }

    public static func notificationRoute(_ notification: JSONValue) -> AppRoute {
        if notification["type"].string == "receiveFollowRequest" { return .followRequests }
        if let noteID = notification["note"]["id"].string, !noteID.isEmpty { return .note(noteID) }
        return .notifications
    }
}
