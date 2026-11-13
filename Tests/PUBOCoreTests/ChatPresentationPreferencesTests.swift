import XCTest
@testable import PUBOCore

final class ChatPresentationPreferencesTests: XCTestCase {
    private func pair(_ scope: [String: JSONValue], _ value: Bool) -> JSONValue {
        .array([.object(scope), .bool(value)])
    }
    func testMissingOrMalformedKeepsDefaultUnspecified() {
        for value in [JSONValue.null, .object([:]), .array([]), .array([.array([.object([:]), .string("true")])])] {
            XCTAssertNil(ChatPresentationPreferences.senderName(in: value, accountID: "me"))
        }
    }
    func testAccountThenServerThenGlobalPrecedence() {
        let global = pair([:], false)
        let server = pair(["server": .string("bolubo.com")], true)
        let account = pair(["server": .string("bolubo.com"), "account": .string("me")], false)
        XCTAssertEqual(ChatPresentationPreferences.senderName(in: .array([global, server]), accountID: "me"), true)
        XCTAssertEqual(ChatPresentationPreferences.senderName(in: .array([account, global, server]), accountID: "me"), false)
        XCTAssertEqual(ChatPresentationPreferences.senderName(in: .array([global, server, account]), accountID: "me"), false)
    }
    func testOtherAccountsServersDevicesAndInvalidScopeCannotLeak() {
        let bad = [
            pair(["server": .string("other.invalid")], true),
            pair(["server": .string("bolubo.com"), "account": .string("other")], true),
            pair(["account": .string("me")], true),
            pair(["device": .string("other-device")], true),
            pair(["server": .number(1)], true),
            pair(["account": .number(1)], true)
        ]
        XCTAssertNil(ChatPresentationPreferences.senderName(in: .array(bad), accountID: "me"))
        XCTAssertEqual(ChatPresentationPreferences.senderName(in: .array(bad + [pair([:], false)]), accountID: "me"), false)
    }
}
