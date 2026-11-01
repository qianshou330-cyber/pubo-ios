import Foundation

public enum HomeContent {
    public static func timelines(user: JSONValue) -> [String] {
        guard user["id"].string != nil else { return [] }
        var result = ["home"]
        if user["policies"]["ltlAvailable"].bool { result += ["local", "hybrid"] }
        if user["policies"]["gtlAvailable"].bool { result.append("global") }
        return result
    }

    public static func chartRows(_ data: JSONValue, limit: Int? = nil) -> [JSONValue] {
        var seen = Set<String>()
        let rows = data["entries"].array.filter {
            guard let id = $0["songId"].string, !id.isEmpty, $0["rank"].int > 0,
                  !$0["groupIds"].array.isEmpty else { return false }
            return seen.insert(id).inserted
        }.sorted { $0["rank"].int < $1["rank"].int }
        return limit.map { Array(rows.prefix($0)) } ?? rows
    }

    public static func chartStatus(_ chart: JSONValue) -> String {
        switch chart["status"].string {
        case "available": return "已更新"
        case "stale": return "上次数据 · 等待更新"
        case "restricted": return "来源访问受限"
        case "unavailable": return "暂时不可用"
        case "disabled": return "暂未启用"
        default: return "等待数据"
        }
    }

    public static func chartScope(_ chart: JSONValue) -> String {
        var parts: [String] = []
        if chart["coverage"].string == "preview" { parts.append("仅来源预览范围") }
        if chart["rankBasis"].string == "playlist_order" { parts.append("歌单顺序，非官方排名") }
        return parts.joined(separator: " · ")
    }

    public static func publicAnnouncements(_ entries: [Record]) -> [Record] {
        Records.merge([], entries.filter { $0["display"].string == "marquee" && !$0["forYou"].bool }, limit: entries.count)
    }
}
