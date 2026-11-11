import Foundation

public enum ProfileFollowAction: Equatable, Sendable {
    case follow, request, cancelRequest, unfollow
    public init(user: Record) {
        if user["isFollowing"].bool { self = .unfollow }
        else if user["hasPendingFollowRequestFromYou"].bool { self = .cancelRequest }
        else { self = user["isLocked"].bool ? .request : .follow }
    }
    public var title: String {
        switch self {
        case .follow: return "关注"
        case .request: return "申请关注"
        case .cancelRequest: return "取消关注申请"
        case .unfollow: return "取消关注"
        }
    }
    public var requiresConfirmation: Bool { self == .cancelRequest || self == .unfollow }
    public var endpoint: String {
        switch self {
        case .follow, .request: return "following/create"
        case .cancelRequest: return "following/requests/cancel"
        case .unfollow: return "following/delete"
        }
    }
}

public enum CollectionListing {
    public static func endpoint(kind: CollectionKind, mode: String) -> String {
        switch kind {
        case .channel: return mode == "search" ? "channels/search" : "channels/" + (mode == "mine" ? "owned" : mode)
        case .gallery: return mode == "mine" ? "users/gallery/posts" : mode == "latest" ? "gallery/posts" : "gallery/featured"
        case .clip: return mode == "favorites" ? "clips/my-favorites" : "clips/list"
        default: return kind.base + "/list"
        }
    }
    public static func paginated(kind: CollectionKind, mode: String) -> Bool {
        !(kind == .list || kind == .antenna
          || (kind == .channel && ["featured", "my-favorites"].contains(mode))
          || (kind == .gallery && ["featured", "popular"].contains(mode))
          || (kind == .clip && mode == "favorites"))
    }
}
