import Foundation

public struct NativePushNotice: Equatable, Sendable {
    public enum Kind: String, Sendable { case chat, notification }
    public let kind: Kind
    public let accountID: String
    public let eventID: String
    public init?(_ payload: JSONValue) {
        let value = payload["pubo"]
        guard value["version"].int == 1, let kind = Kind(rawValue: value["kind"].string ?? ""),
              let account = value["accountId"].string, let event = value["eventId"].string,
              [account, event].allSatisfy({ $0.range(of: "^[a-zA-Z0-9]{1,32}$", options: .regularExpression) != nil }) else { return nil }
        self.kind = kind; accountID = account; eventID = event
    }
    public func belongs(to userID: String?) -> Bool { userID == accountID }
}
