import Foundation
import PUBOCore

enum NativeStrings {
    private static let achievements: JSONValue = {
        guard let url = Bundle.main.url(forResource: "Achievements.zh-CN", withExtension: "json"), let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JSONValue.self, from: bytes) else { return .null }
        return value["items"]
    }()
    static func achievement(_ key: String, field: String = "title") -> String { achievements[key][field].string ?? (field == "title" ? key : "") }
}
