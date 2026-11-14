import Foundation

/// A confirmation belongs to the account and screen where it was requested.
/// This is a client-side stale-intent guard, not a replacement for server authorization.
public struct RoomMessageDeletionIntent: Equatable, Sendable {
    public let ownerID: String
    public let generation: UUID
    public let screenID: UUID
    public let roomID: String
    public let messageID: String

    public init?(ownerID: String, generation: UUID, screenID: UUID, roomID: String, message: Record) {
        guard !ownerID.isEmpty, !roomID.isEmpty, !message.id.isEmpty,
              message["fromUserId"].string == ownerID,
              message["toRoomId"].string == roomID, message["recalledAt"].isNull else { return nil }
        self.ownerID = ownerID; self.generation = generation; self.screenID = screenID
        self.roomID = roomID; self.messageID = message.id
    }

    public func matches(ownerID: String?, generation: UUID, screenID: UUID, roomID: String, active: Bool) -> Bool {
        active && self.ownerID == ownerID && self.generation == generation && self.screenID == screenID && self.roomID == roomID
    }

    public func permits(_ message: Record?) -> Bool {
        guard let message else { return false }
        return message.id == messageID && message["fromUserId"].string == ownerID &&
            message["toRoomId"].string == roomID && message["recalledAt"].isNull
    }
}
