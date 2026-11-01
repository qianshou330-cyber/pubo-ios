import XCTest
@testable import PUBOCore

final class NativePushTests: XCTestCase {
    func testPushRoutingRequiresAccountAndKnownVersion() {
        let payload: JSONValue = .object(["pubo": .object(["version": .number(1), "kind": .string("chat"), "accountId": .string("account1"), "eventId": .string("message1")])])
        let notice = NativePushNotice(payload)
        XCTAssertNotNil(notice); XCTAssertTrue(notice!.belongs(to: "account1")); XCTAssertFalse(notice!.belongs(to: "account2")); XCTAssertFalse(notice!.belongs(to: nil))
        for (key, value) in [("version", JSONValue.number(2)), ("kind", .string("openURL")), ("accountId", .string("")), ("eventId", .string("https://outside.example"))] {
            var modified = payload["pubo"].object; modified[key] = value
            XCTAssertNil(NativePushNotice(.object(["pubo": .object(modified)])))
        }
    }
}
