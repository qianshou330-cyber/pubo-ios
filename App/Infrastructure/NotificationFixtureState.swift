#if DEBUG
import Foundation
import Combine
import PUBOCore

/// The same synthetic records drive the two visual captures. Only the fixture transport can reach this.
struct NotificationFixtureState {
    @MainActor static let stream = PassthroughSubject<Record, Never>()
    private static let cases: JSONValue = {
        guard let url = Bundle.main.url(forResource: "NotificationVisualCases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            preconditionFailure("Missing synthetic notification cases")
        }
        return value
    }()
    private var unread = true
    private var fullReads = 0
    private var pendingRequest = true

    private func page(_ rows: [JSONValue], _ params: JSONValue) -> JSONValue {
        let start: Int
        if let until = params["untilId"].string {
            guard let index = rows.firstIndex(where: { $0["id"].string == until }) else { return .array([]) }
            start = index + 1
        } else { start = 0 }
        let size = min(max(params["limit"].int, 1), 100)
        return .array(Array(rows.dropFirst(start).prefix(size)))
    }

    mutating func response(path: String, body: JSONValue, profile: JSONValue, arguments: [String]) -> JSONValue? {
        let source = Self.cases
        switch path {
        case "i":
            var values = profile.object
            values["hasUnreadNotification"] = .bool(unread)
            values["unreadNotificationsCount"] = .number(unread ? 12 : 0)
            return .object(values)
        case "i/notifications", "i/notifications-grouped":
            let included = body["includeTypes"].array.compactMap(\.string)
            let excluded = body["excludeTypes"].array.compactMap(\.string)
            if body["markAsRead"].isNull || body["markAsRead"].bool { unread = false }
            if body["untilId"].isNull && included.isEmpty && excluded.isEmpty { fullReads += 1 }
            var rows = source["notifications"].array
            if arguments.contains("--notifications-live") && fullReads == 1 && included.isEmpty && excluded.isEmpty && body["untilId"].isNull {
                let incoming = Record(source["liveNotification"])
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(2_500))
                    Self.stream.send(incoming)
                }
            }
            if arguments.contains("--notifications-refresh") && fullReads > 1 {
                rows.insert(source["liveNotification"], at: 0)
            }
            return page(rows.filter { row in
                guard let raw = row["type"].string, let base = raw.components(separatedBy: ":").first else { return false }
                return (included.isEmpty || included.contains(base)) && !excluded.contains(base)
            }, body)
        case "notifications/mark-all-as-read":
            unread = false
            return .null
        case "notes/mentions":
            return page(source[body["visibility"].string == "specified" ? "directNotes" : "mentions"].array, body)
        case "notes/show":
            return source["notes"].array.first { $0["id"] == body["noteId"] } ?? .null
        case "users/show":
            let users = source["users"].array + [profile]
            if !body["userIds"].isNull {
                return .array(body["userIds"].array.compactMap { id in users.first { $0["id"] == id } })
            }
            return users.first { $0["id"] == body["userId"] || $0["username"] == body["username"] } ?? .null
        case "drive/files/show":
            return source["file"]["id"] == body["fileId"] ? source["file"] : .null
        case "chat/rooms/show":
            return source["room"]["id"] == body["roomId"] ? source["room"] : .null
        case "following/requests/list":
            return .array(pendingRequest ? [.object(["id": .string("syntheticrequest"), "follower": source["users"].array[0]])] : [])
        case "following/requests/accept", "following/requests/reject":
            if body["userId"] == source["users"].array[0]["id"] { pendingRequest = false }
            return .null
        case "users/achievements":
            return .array([.object(["name": .string("notes1"), "unlockedAt": .number(1_794_360_000_000)])])
        default:
            return nil
        }
    }
}
#endif
