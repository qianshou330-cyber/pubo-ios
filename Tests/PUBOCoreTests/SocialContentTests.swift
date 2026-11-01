import XCTest
@testable import PUBOCore

final class SocialContentTests: XCTestCase {
    func testPollRejectsDuplicatesEmptyOversizeAndExpired() throws {
        var poll = PollDraft()
        for choices in [["A", " A "], ["", "B"], [String(repeating: "中", count: 51), "B"], Array(repeating: "A", count: 11)] {
            poll.choices = choices; XCTAssertThrowsError(try poll.request())
        }
        poll.choices = ["A", "B"]; poll.expiresAt = Date(timeIntervalSince1970: 0)
        XCTAssertThrowsError(try poll.request())
    }
    func testPollRoundTripRetainsAbsoluteExpiry() throws {
        var draft = PollDraft(); draft.choices = [" A ", "B"]; draft.multiple = true
        draft.expiresAt = Date(timeIntervalSince1970: 2_000_000_000)
        let restored = try JSONDecoder().decode(PollDraft.self, from: JSONEncoder().encode(draft))
        let request = try restored.request(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(request["choices"], .strings(["A", "B"]))
        XCTAssertEqual(request["expiresAt"].int, 2_000_000_000_000)
        let response: JSONValue = .object(["choices": .array([.object(["text": .string("A")]), .object(["text": .string("B")])]), "multiple": .bool(true), "expiresAt": .string("2033-05-18T03:33:20.000Z")])
        XCTAssertTrue(SocialContent.pollReceipt(response, request: request))
        XCTAssertFalse(SocialContent.pollReceipt(response, request: nil))
        var wrong = request.object; wrong["multiple"] = .bool(false)
        XCTAssertFalse(SocialContent.pollReceipt(response, request: .object(wrong)))
        wrong = request.object; wrong["choices"] = .strings(["B", "A"])
        XCTAssertFalse(SocialContent.pollReceipt(response, request: .object(wrong)))
    }
    func testChatLateSnapshotCannotRestoreEditedOrRecalledContent() {
        let edited = message("a", revision: 2, text: "new")
        let old = message("a", revision: 1, text: "old")
        XCTAssertEqual(ChatRecords.merge([edited], [old]).first?.text, "new")
        let recalled = message("a", revision: 3, text: "", recalled: true)
        XCTAssertEqual(ChatRecords.merge([recalled], [edited]).first, recalled)
        XCTAssertEqual(ChatRecords.merge([recalled], [message("a", revision: 4, text: "resurrect")]).first, recalled)
    }
    func testChatAuthoritativeMissingAndStateWithoutReactionOwners() {
        let first = message("a", revision: 0, text: "one")
        var detailed = message("b", revision: 1, text: "two").raw.object
        detailed["reactions"] = .array([.object(["reaction": .string("❤️"), "user": .object(["id": .string("self")])])])
        var state = detailed; state["reactions"] = .array([.object(["reaction": .string("❤️")])])
        let result = ChatRecords.merge([first, Record(.object(detailed))], [Record(.object(state))], missingIDs: ["a"])
        XCTAssertEqual(result.map(\.id), ["b"])
        XCTAssertTrue(result[0]["reactions"].array[0]["user"].isNull)
    }
    private func message(_ id: String, revision: Int, text: String, recalled: Bool = false) -> Record {
        Record(.object(["id": .string(id), "revision": .number(Double(revision)), "text": .string(text), "recalledAt": recalled ? .string("2026-11-02T00:00:00Z") : .null]))
    }
}
