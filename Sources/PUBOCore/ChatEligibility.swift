import Foundation

/// UI preflight only. The server remains authoritative for every mutation.
public enum ChatEligibility {
    public static func problem(account: Record?, peer: Record? = nil) -> String? {
        switch account?["policies"]["chatAvailability"].string {
        case "available": break
        case "readonly": return "当前账号的聊天为只读，不能发送消息或创建聊天。"
        case "unavailable": return "当前账号暂不可使用聊天。"
        default: return "暂未取得聊天权限，请刷新账号信息后重试。"
        }
        if let peer {
            if let host = peer["host"].string, !host.isEmpty { return "暂不支持与其他服务器的用户聊天。" }
            // Lightweight user records may omit canChat. Do not interpret absence as false.
            if peer["canChat"] == .bool(false) { return "对方当前无法使用聊天，暂时不能发送消息。" }
        }
        return nil
    }
}

public enum ChatSearchPresentation {
    public static func sender(_ message: Record, viewerID: String?) -> String {
        if let viewerID, message["fromUserId"].string == viewerID { return "你" }
        return identity(message["fromUser"], fallbackID: message["fromUserId"].string)
    }
    public static func destination(_ message: Record, viewerID: String?) -> String {
        if let roomID = message["toRoomId"].string {
            return "群聊 · " + (message["toRoom"]["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? roomID)
        }
        let outgoing = viewerID != nil && message["fromUserId"].string == viewerID
        let userKey = outgoing ? "toUser" : "fromUser"
        return "私信 · " + identity(message[userKey], fallbackID: message[userKey + "Id"].string)
    }
    private static func identity(_ value: JSONValue, fallbackID: String?) -> String {
        let name = value["name"].string.flatMap { $0.isEmpty ? nil : $0 }
        if let username = value["username"].string, !username.isEmpty {
            let host = value["host"].string.map { "@" + $0 } ?? ""
            return (name.map { $0 + " " } ?? "") + "@" + username + host
        }
        return name ?? fallbackID ?? "未知用户"
    }
    public static func showsEmpty(completed: Bool, busy: Bool, hasError: Bool, count: Int) -> Bool {
        completed && !busy && !hasError && count == 0
    }
}
