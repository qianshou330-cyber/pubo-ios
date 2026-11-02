import Foundation

public struct ChartMovement: Equatable, Sendable {
    public let label: String
    public let explanation: String
    public let direction: Int
    public let basis: String
    public init(_ row: JSONValue) {
        let source = row["sourceMovement"]
        let amount = Self.integer(source["amount"])
        if ["up", "down"].contains(source["type"].string ?? ""), let amount, amount > 0 {
            let up = source["type"].string == "up"
            label = "\(up ? "↑" : "↓")\(amount)"; explanation = "\(up ? "上升" : "下降") \(amount) 位"
            direction = up ? 1 : -1; basis = "来源标注"
        } else if source["type"].string == "new" {
            label = "NEW"; explanation = "来源标记新进榜"; direction = 0; basis = "来源标注"
        } else if source["type"].string == "same" {
            label = "＝"; explanation = "名次不变"; direction = 0; basis = "来源标注"
        } else if let previous = Self.integer(row["previousRank"]), previous > 0, let change = Self.integer(row["change"]) {
            label = change > 0 ? "↑\(change)" : change < 0 ? "↓\(-change)" : "＝"
            explanation = change > 0 ? "上升 \(change) 位" : change < 0 ? "下降 \(-change) 位" : "名次不变"
            direction = change == 0 ? 0 : change > 0 ? 1 : -1; basis = "本站上次可比较记录"
        } else { label = "—"; explanation = "暂无可比较记录"; direction = 0; basis = "无对比" }
    }
    public static func integer(_ value: JSONValue) -> Int? {
        guard case .number(let number) = value, number.isFinite, number.rounded() == number,
              number > Double(Int.min), number < Double(Int.max) else { return nil }
        return Int(number)
    }
}

public struct KpopPreferences: Codable, Equatable, Sendable {
    public static let chartKeys = ["melon-top100", "melon-hot100", "melon-hot100-d30", "melon-daily", "genie-realtime", "bugs-realtime", "flo", "apple", "spotify", "tencent", "billboard-korea-global-k-songs"]
    public static let groups: [(String, String)] = [("a2o-lite", "A2O LITE"), ("hearts2hearts", "Hearts2Hearts"), ("kiiikiii", "KiiiKiii"), ("baby-dont-cry", "Baby DONT Cry"), ("ifeye", "ifeye"), ("babymonster", "BABYMONSTER"), ("illit", "ILLIT"), ("meovv", "MEOVV"), ("triples", "tripleS"), ("aespa", "aespa"), ("newjeans", "NewJeans"), ("le-sserafim", "LE SSERAFIM"), ("ive", "IVE")]
    public var chartKey = "melon-top100"
    public var lastMelonChart = "melon-top100"
    public var groupID = ""
    public init() {}
    public var validated: Self {
        var result = self
        if !Self.chartKeys.contains(chartKey) { result.chartKey = "melon-top100" }
        if !Self.chartKeys.prefix(4).contains(lastMelonChart) { result.lastMelonChart = "melon-top100" }
        if !Self.groups.contains(where: { $0.0 == groupID }) { result.groupID = "" }
        return result
    }
    public mutating func selectChart(_ key: String) {
        guard Self.chartKeys.contains(key) else { return }; chartKey = key
        if key.hasPrefix("melon-") { lastMelonChart = key }
    }
}

public struct ChartHistoryPoint: Identifiable, Sendable {
    public let id: Int
    public let date: Date
    public let rank: Int?
    public let segment: Int
    public let value: JSONValue
    public static func parse(_ history: JSONValue) -> [Self] {
        let official = history["basis"].string == "official_period"
        let from = history["from"].string.flatMap(SocialContent.date)
        let to = history["to"].string.flatMap(SocialContent.date)
        var values: [(Date, JSONValue)] = []
        for point in history["points"].array {
            guard let raw = point[official ? "sourcePeriod" : "observedAt"].string else { continue }
            let date = SocialContent.date(raw.count == 10 && official ? raw + "T00:00:00+09:00" : raw)
            guard let date, from.map({ date >= $0 }) ?? true, to.map({ date <= $0 }) ?? true else { continue }
            values.append((date, point))
        }
        var segment = 0
        return values.sorted { $0.0 < $1.0 }.enumerated().map { index, value in
            let (date, point) = value
            if point["gapBefore"].bool { segment += 1 }
            let rank = point["result"].string == "ranked" ? ChartMovement.integer(point["rank"]).flatMap { $0 > 0 ? $0 : nil } : nil
            let result = Self(id: index, date: date, rank: rank, segment: segment, value: point)
            if rank == nil { segment += 1 }; return result
        }
    }
}
