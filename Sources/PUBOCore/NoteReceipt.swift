import Foundation

/// A successful HTTP response is not enough to discard a recoverable post draft.
public enum NoteReceipt {
    public static func matches(_ response: JSONValue, authorID: String, request: [String: JSONValue]) -> Bool {
        let note = Record(response["createdNote"])
        return !note.id.isEmpty && note.user.id == authorID &&
            note.text == (request["text"]?.string ?? "") &&
            note["visibility"].string == (request["visibility"]?.string ?? "public") &&
            note["cw"].string == request["cw"]?.string &&
            note["replyId"].string == request["replyId"]?.string &&
            note["renoteId"].string == request["renoteId"]?.string &&
            note["files"].array.compactMap { $0["id"].string } == (request["fileIds"]?.array.compactMap(\.string) ?? [])
    }
}
