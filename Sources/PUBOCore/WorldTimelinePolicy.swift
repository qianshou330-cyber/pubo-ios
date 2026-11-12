import Foundation

/// The new world feed reuses the site's existing public timeline, not geography
/// or a new recommendation algorithm. Server policy remains authoritative.
public enum WorldTimelinePolicy {
    public static func choices(user: JSONValue) -> [String] {
        guard user["id"].string != nil else { return [] }
        return user["policies"]["ltlAvailable"].bool ? ["local", "home"] : ["home"]
    }
    public static func title(for timeline: String) -> String {
        timeline == "local" ? "推荐" : "关注"
    }
    public static func normalize(_ preferences: inout TimelinePreferences, user: JSONValue) {
        let available = choices(user: user)
        if !available.contains(preferences.selected) {
            preferences.selected = available.contains("local") ? "local" : "home"
        }
        if preferences.onlyFiles { preferences.withReplies = false }
    }
}
