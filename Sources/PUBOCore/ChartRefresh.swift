import Foundation

public struct ChartRankChange: Equatable, Hashable, Sendable {
    public let from: Int
    public let to: Int
    public var offset: Double { to < from ? -6 : 6 }
}

/// A rank transition is an observed refresh, not the source's up/down label.
public enum ChartRefresh {
    public static func changes(previous: JSONValue, incoming: JSONValue, contextMatches: Bool = true) -> [String: ChartRankChange] {
        let oldChart = previous["selected"].isNull ? previous["chart"] : previous["selected"]
        let newChart = incoming["selected"].isNull ? incoming["chart"] : incoming["selected"]
        guard contextMatches, oldChart["status"].string == "available", newChart["status"].string == "available",
              let key = oldChart["chartKey"].string, key == newChart["chartKey"].string else { return [:] }
        var old: [String: Int] = [:]
        for row in HomeContent.chartRows(previous) { if let id = row["songId"].string { old[id] = row["rank"].int } }
        var changes: [String: ChartRankChange] = [:]
        for row in HomeContent.chartRows(incoming) {
            guard let id = row["songId"].string, let rank = old[id], rank != row["rank"].int else { continue }
            changes[id] = ChartRankChange(from: rank, to: row["rank"].int)
        }
        return changes
    }
}

public enum ChartClock {
    public static func korean(_ raw: String?) -> String? {
        guard let raw, let date = SocialContent.date(raw) else { return nil }
        return korean(date)
    }
    public static func korean(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 9 * 3600)
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.string(from: date) + " KST"
    }
}
