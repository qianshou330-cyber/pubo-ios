import Foundation

public struct TimelinePreferences: Codable, Equatable, Sendable {
    public var selected = "local"
    public var withRenotes = true
    public var withReplies = false
    public var withSensitive = true
    public var onlyFiles = false
    public var fixedComposer = false
    public init() {}
    public mutating func normalize(available: [String]) {
        if !available.contains(selected) { selected = available.contains("local") ? "local" : "home" }
        if onlyFiles { withReplies = false }
    }
    public mutating func setReplies(_ value: Bool) { withReplies = value; if value { onlyFiles = false } }
    public mutating func setOnlyFiles(_ value: Bool) { onlyFiles = value; if value { withReplies = false } }
    public var parameters: [String: JSONValue] {
        var result: [String: JSONValue] = ["withRenotes": .bool(withRenotes), "withFiles": .bool(onlyFiles)]
        if ["local", "hybrid"].contains(selected) { result["withReplies"] = .bool(withReplies && !onlyFiles) }
        return result
    }
    public var requestKey: String { "\(selected)-\(withRenotes)-\(withReplies)-\(onlyFiles)" }
    public func accepts(_ note: Record, accountID: String?) -> Bool {
        if !withRenotes && NoteContext.isRepost(note) { return false }
        let displayed = NoteContext.displayed(note)
        if onlyFiles && displayed["files"].array.isEmpty && displayed["fileIds"].array.isEmpty { return false }
        return true // Server applies visibility, replies, muting, and role policy.
    }
}

public struct NoteStreamEvent: Equatable, Sendable {
    public var sequence = UUID()
    public let id: String
    public let kind: String
    public let body: JSONValue
    public init(id: String, kind: String, body: JSONValue) { self.id = id; self.kind = kind; self.body = body }
    public func applying(to record: Record, accountID: String?) -> Record {
        Record(update(record.raw, accountID: accountID, depth: 0))
    }
    private func update(_ value: JSONValue, accountID: String?, depth: Int) -> JSONValue {
        guard depth < 4, !value.object.isEmpty else { return value }
        var map = value.object
        if value["id"].string == id {
            if kind == "replaced", body["id"].string == id { return body }
            if kind == "deleted" { return .object(["id": .string(id), "isHidden": .bool(true), "deleted": .bool(true)]) }
            if kind == "reacted" || kind == "unreacted", let reaction = body["reaction"].string {
                var reactions = value["reactions"].object
                let ownEvent = body["userId"].string == accountID && accountID != nil
                let alreadyApplied = ownEvent && (kind == "reacted" ? value["myReaction"].string == reaction : value["myReaction"].isNull)
                let count = max(0, (reactions[reaction]?.int ?? 0) + (alreadyApplied ? 0 : kind == "reacted" ? 1 : -1))
                if count == 0 { reactions.removeValue(forKey: reaction) } else { reactions[reaction] = .number(Double(count)) }
                map["reactions"] = .object(reactions)
                map["reactionCount"] = .number(Double(reactions.values.reduce(0) { $0 + $1.int }))
                if ownEvent { map["myReaction"] = kind == "reacted" ? .string(reaction) : .null }
                if let name = body["emoji"]["name"].string, let url = body["emoji"]["url"].string {
                    var emojis = value["reactionEmojis"].object; emojis[name] = .string(url); map["reactionEmojis"] = .object(emojis)
                }
            } else if kind == "pollVoted" {
                var poll = value["poll"].object; var choices = value["poll"]["choices"].array
                let choice = body["choice"].int
                if choices.indices.contains(choice) {
                    var item = choices[choice].object
                    let alreadyApplied = accountID != nil && body["userId"].string == accountID && choices[choice]["isVoted"].bool
                    item["votes"] = .number(Double(choices[choice]["votes"].int + (alreadyApplied ? 0 : 1)))
                    if accountID != nil && body["userId"].string == accountID { item["isVoted"] = .bool(true) }
                    choices[choice] = .object(item); poll["choices"] = .array(choices); map["poll"] = .object(poll)
                }
            }
        }
        for key in ["reply", "renote"] where !value[key].isNull { map[key] = update(value[key], accountID: accountID, depth: depth + 1) }
        return .object(map)
    }
}

public struct TimelineState: Sendable {
    public private(set) var notes: [Record] = []
    public private(set) var pending: [Record] = []
    public private(set) var deleted = Set<String>()
    public private(set) var olderCursor: String?
    public init() {}
    public mutating func reset() { self = Self() }
    private func cleaned(_ items: [Record], accountID: String?) -> [Record] {
        items.filter { !deleted.contains($0.id) && !(NoteContext.isRepost($0) && deleted.contains(NoteContext.displayed($0).id)) }.map { record in
            deleted.reduce(record) { result, id in NoteStreamEvent(id: id, kind: "deleted", body: .null).applying(to: result, accountID: accountID) }
        }
    }
    public mutating func page(_ items: [Record], older: Bool, preferences: TimelinePreferences, accountID: String?) {
        let values = cleaned(items, accountID: accountID).filter { preferences.accepts($0, accountID: accountID) }
        notes = Records.merge(notes, values, limit: max(2_000, notes.count + values.count))
        if older || olderCursor == nil { olderCursor = items.last?.id ?? olderCursor }
        let visibleIDs = Set(notes.map(\.id)); pending.removeAll { visibleIDs.contains($0.id) }
    }
    public mutating func receive(_ note: Record, atTop: Bool, preferences: TimelinePreferences, accountID: String?) {
        guard let note = cleaned([note], accountID: accountID).first else { return }
        guard !note.id.isEmpty, !deleted.contains(note.id), preferences.accepts(note, accountID: accountID) else { return }
        if notes.contains(where: { $0.id == note.id }) || atTop { notes = Records.merge(notes, [note], limit: max(2_000, notes.count + 1)) }
        else { pending = Records.merge(pending, [note], limit: 2_000) }
    }
    public mutating func revealPending() { notes = Records.merge(notes, pending, limit: max(2_000, notes.count + pending.count)); pending = [] }
    public mutating func apply(_ event: NoteStreamEvent, accountID: String?) {
        if event.kind == "deleted" { deleted.insert(event.id) }
        notes = cleaned(notes.map { event.applying(to: $0, accountID: accountID) }, accountID: accountID)
        pending = cleaned(pending.map { event.applying(to: $0, accountID: accountID) }, accountID: accountID)
    }
}

public enum TimelinePresentation {
    public static func visibilityIcon(_ value: String?) -> String {
        switch value { case "home": return "house"; case "followers": return "lock"; case "specified": return "envelope"; default: return "globe" }
    }
    public static func visibilityLabel(_ value: String?) -> String {
        switch value { case "home": return "首页可见"; case "followers": return "关注者可见"; case "specified": return "指定用户可见"; default: return "公开" }
    }
    public static func sensitive(_ note: Record) -> Bool { NoteContext.displayed(note)["files"].array.contains { $0["isSensitive"].bool } }
    public static func capturedIDs(_ notes: [Record]) -> Set<String> {
        var ids = Set<String>()
        func visit(_ value: JSONValue, depth: Int) {
            guard depth < 4 else { return }
            if let id = value["id"].string { ids.insert(id) }
            for key in ["reply", "renote"] { if !value[key].isNull { visit(value[key], depth: depth + 1) } }
        }
        for note in notes { visit(note.raw, depth: 0) }
        return ids
    }
}
