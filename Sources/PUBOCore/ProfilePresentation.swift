import Foundation

/// Form limits mirror the H5 profile editor, not a claim about every backend limit.
public enum ProfilePresentation {
    public static let nameLimit = 30
    public static let descriptionLimit = 500
    public static let fieldLimit = 16
    public static func length(_ text: String) -> Int { text.unicodeScalars.count }
    public static func optionalText(_ text: String) -> JSONValue { text.isEmpty ? .null : .string(text) }
    public static func validBirthday(_ text: String) -> Bool {
        if text.isEmpty { return true }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        return checked.year == year && checked.month == month && checked.day == day
    }
    public static func validationError(name: String, description: String, birthday: String, fieldCount: Int) -> String? {
        if length(name) > nameLimit { return "昵称最多 30 个字符。" }
        if length(description) > descriptionLimit { return "简介最多 500 个字符。" }
        if fieldCount > fieldLimit { return "附加资料最多 16 项。" }
        if !validBirthday(birthday) { return "生日请填写有效日期，格式为 YYYY-MM-DD；留空可清除。" }
        return nil
    }
    public static func fields(_ rows: [(String, String)]) -> JSONValue {
        .array(rows.filter { !$0.0.isEmpty && !$0.1.isEmpty }.map { .object(["name": .string($0.0), "value": .string($0.1)]) })
    }
    public static func verified(_ value: String, links: JSONValue) -> Bool {
        !value.isEmpty && links.array.compactMap(\.string).contains(value)
    }
}
