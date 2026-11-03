import Foundation

public enum TextInsertion {
    public static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location == NSNotFound ? length : range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
    public static func insert(_ value: String, into text: inout String, selection: inout NSRange) {
        let range = clamped(selection, in: text)
        text = (text as NSString).replacingCharacters(in: range, with: value)
        selection = NSRange(location: range.location + (value as NSString).length, length: 0)
    }
}

public enum NoteContext {
    /// A quote with files or a poll is not a plain repost, even when its text is empty.
    public static func isRepost(_ note: Record) -> Bool {
        note.text.isEmpty && note["files"].array.isEmpty && note["fileIds"].array.isEmpty && note["poll"].isNull
            && (!note["renoteId"].isNull || !note["renote"]["id"].isNull)
    }
    public static func displayed(_ note: Record) -> Record {
        isRepost(note) && !note["renote"]["id"].isNull ? Record(note["renote"]) : note
    }
    public static func summary(_ note: Record) -> String {
        if note["isHidden"].bool { return "原帖不可见" }
        if let cw = note["cw"].string { return cw.isEmpty ? "原帖含内容提示，点击查看" : cw }
        if !note.text.isEmpty { return note.text }
        if !note["files"].array.isEmpty { return "[附件]" }
        if !note["poll"].isNull { return "[投票]" }
        return "查看原帖"
    }
}

public enum SendFeedback {
    public static func length(_ text: String) -> Int { text.unicodeScalars.count }
    public static func limitError(_ text: String, limit: Int, label: String = "消息") -> String? {
        let extra = length(text) - limit
        return extra > 0 ? "\(label)超出 \(extra) 个字符，最多 \(limit) 个；内容已保留。" : nil
    }
    public static func messageSummary(_ message: JSONValue) -> String {
        if !message["recalledAt"].isNull { return "消息已撤回" }
        if let text = message["text"].string, !text.isEmpty { return text }
        let files = message["attachments"].array
        guard let file = files.first else { return message["file"].isNull ? "暂无消息" : "[文件]" }
        let type = file["mime"].string ?? ""
        let kind = file["kind"].string == "voice" ? "语音" : type.hasPrefix("image/") ? "图片" : type.hasPrefix("video/") ? "视频" : "文件"
        return "[\(kind)]" + (files.count > 1 ? " \(files.count) 个附件" : "")
    }
}

public enum NotificationTarget: Equatable, Sendable {
    case note(String), user(String), room(String), achievements, file(String), sessions, connections, followRequests, scheduled, profile, none
    public static func resolve(_ item: Record) -> Self {
        switch item["type"].string {
        case "chatRoomInvitationReceived":
            if let id = item["invitation"]["room"]["id"].string ?? item["invitation"]["roomId"].string, !id.isEmpty { return .room(id) }
            return .none
        case "achievementEarned": return .achievements
        case "exportCompleted":
            if let id = item["fileId"].string, !id.isEmpty { return .file(id) }
            return .none
        case "login": return .sessions
        case "createToken": return .connections
        case "receiveFollowRequest": return .followRequests
        case "scheduledNotePostFailed": return .scheduled
        case "roleAssigned": return .profile
        default: break
        }
        if let id = item["note"]["id"].string, !id.isEmpty { return .note(id) }
        if item["type"].string == "scheduledNotePosted" { return .scheduled }
        if !item.user.id.isEmpty { return .user(item.user.id) }
        return .none
    }
}
