import Foundation

/// Credentials never leave the device Keychain. Optional labels decode the build 22 format.
public struct LoginSecret: Codable, Equatable, Sendable {
    public let token: String
    public let userID: String
    public let username: String?
    public let displayName: String?
    public init(token: String, userID: String, username: String? = nil, displayName: String? = nil) {
        self.token = token; self.userID = userID; self.username = username; self.displayName = displayName
    }
}
public struct AccountVault: Codable, Equatable, Sendable {
    public private(set) var accounts: [LoginSecret]
    public private(set) var activeID: String?
    public init(legacy: LoginSecret? = nil) { accounts = legacy.map { [$0] } ?? []; activeID = legacy?.userID }
    public var active: LoginSecret? { accounts.first { $0.userID == activeID } }
    public mutating func install(_ secret: LoginSecret) {
        accounts.removeAll { $0.userID == secret.userID }; accounts.append(secret); activeID = secret.userID
    }
    public mutating func remove(_ id: String) { accounts.removeAll { $0.userID == id }; if activeID == id { activeID = nil } }
}
