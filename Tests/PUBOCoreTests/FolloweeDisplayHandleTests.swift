import XCTest
@testable import PUBOCore

final class FolloweeDisplayHandleTests: XCTestCase {
    private func user(_ username: String, host: JSONValue?, id: String = "synthetic") -> Record {
        var fields: [String: JSONValue] = ["id": .string(id), "username": .string(username)]
        fields["host"] = host
        return Record(.object(fields))
    }

    func testExistingFollowRowsDistinguishIdenticalLocalAndRemoteUsernamesWithoutRemovingMalformedRow() throws {
        let users = [user("friend", host: .null, id: "local"),
                     user("friend", host: .string("Remote.Example"), id: "remote"),
                     user("friend", host: .string("https://remote.example"), id: "malformed")]
        let rows: [JSONValue] = users.map { .object(["id": .string("relation-" + $0.id), "followee": $0.raw]) }
        var page = FollowListPage()
        try page.apply(.array(rows), reset: true, followers: false, limit: 3)
        let loaded = page.rows.map { Record($0["followee"]) }
        XCTAssertEqual(loaded, users)
        XCTAssertEqual(loaded.map { FolloweeDisplayHandle.text(for: $0) }, ["@friend", "@friend@Remote.Example", nil])
        XCTAssertEqual(page.cursor, "relation-malformed")
        XCTAssertTrue(page.hasMore)
    }

    func testLocalSignupAndArchivedSystemNames() {
        for valid in ["friend", "relation031", "Fixture_01", String(repeating: "a", count: 20),
                      "system.actor", "system.relay", "system.proxy"] {
            XCTAssertEqual(FolloweeDisplayHandle.text(for: user(valid, host: .null)), "@" + valid)
        }
        for invalid in ["", " friend", "friend\n", "user.other", "user-name", String(repeating: "a", count: 21), "朋友"] {
            XCTAssertNil(FolloweeDisplayHandle.text(for: user(invalid, host: .null)), invalid)
        }
    }

    func testRemoteActorAcceptsRepeatedInteriorPunctuationAndExact128ByteLimit() {
        let maxUsername = "A" + String(repeating: ".-", count: 63) + "_"
        for valid in ["_", "A..-._--B", maxUsername] {
            XCTAssertEqual(FolloweeDisplayHandle.text(for: user(valid, host: .string("Remote.Example"))),
                           "@\(valid)@Remote.Example")
        }
        for invalid in ["", ".actor", "-actor", "actor-", "actor.", "a@b", "a b", "friend\n", "bé", maxUsername + "b"] {
            XCTAssertNil(FolloweeDisplayHandle.text(for: user(invalid, host: .string("Remote.Example"))), invalid)
        }
    }

    func testDNSPunycodeCaseAndPortAreDisplayedAsSupplied() {
        let label = String(repeating: "A", count: 63)
        let fullDomain = [label, label, label, String(repeating: "b", count: 61)].joined(separator: ".") // 253 bytes.
        for host in ["A.Example", "XN--BCHER-KVA.Example:8443", "Remote.Example:65535", fullDomain + ":65535"] {
            XCTAssertEqual(FolloweeDisplayHandle.text(for: user("Remote_1", host: .string(host))), "@Remote_1@" + host)
        }
    }

    func testBadHostCannotTurnARemoteRowIntoAnApparentlyLocalHandle() {
        let malformed = ["", " ", " remote.example", "remote.example\n", "remote..example", "remote.example.",
                         "-remote.example", "remote-.example", "remote_name.example", "bücher.example", "https://remote.example",
                         "remote.example/path", "user@remote.example", "remote.example?q=x", "remote.example#f", "[::1]",
                         "remote.example:", "remote.example:0", "remote.example:65536", "remote.example:+9",
                         "remote.example:８０", "remote.example:80:81", "remote.example:000080",
                         String(repeating: "a", count: 64) + ".example",
                         (1...4).map { _ in String(repeating: "a", count: 63) }.joined(separator: ".")]
        let other: [JSONValue?] = [nil, .number(443), .bool(false), .object([:]), .array([])]
        let badHosts = malformed.map { Optional(JSONValue.string($0)) } + other
        for host in badHosts {
            XCTAssertNil(FolloweeDisplayHandle.text(for: user("friend", host: host)), String(describing: host))
        }
        XCTAssertNil(FolloweeDisplayHandle.text(for: Record(.object(["host": .null]))))
    }
}
