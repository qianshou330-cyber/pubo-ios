import XCTest
@testable import PUBOCore

final class TimelineStateTests: XCTestCase {
    private func note(_ id: String, _ fields: [String: JSONValue] = [:]) -> Record {
        var data = fields; data["id"] = .string(id); return Record(.object(data))
    }
    func testFirstUseAndExistingChoice() {
        var p = TimelinePreferences(); XCTAssertEqual(p.selected, "local")
        p.selected = "home"; p.normalize(available: ["home", "local"]); XCTAssertEqual(p.selected, "home")
        p.selected = "local"; p.normalize(available: ["home"]); XCTAssertEqual(p.selected, "home")
    }
    func testFiltersAreMutuallyExclusiveAndUseServerParameterNames() {
        var p = TimelinePreferences(); p.setReplies(true); p.setOnlyFiles(true)
        XCTAssertFalse(p.withReplies); XCTAssertEqual(p.parameters["withFiles"], .bool(true))
        p.setReplies(true); XCTAssertFalse(p.onlyFiles)
        p.selected = "global"; XCTAssertNil(p.parameters["withReplies"])
        XCTAssertNil(p.parameters["withSensitive"])
    }
    func testPendingDeduplicationAndStableRawPaginationCursor() {
        var state = TimelineState(); let p = TimelinePreferences()
        state.page([note("004"), note("003")], older: false, preferences: p, accountID: "me")
        state.receive(note("005"), atTop: false, preferences: p, accountID: "me")
        state.receive(note("005"), atTop: false, preferences: p, accountID: "me")
        XCTAssertEqual(state.notes.map(\.id), ["004", "003"]); XCTAssertEqual(state.pending.count, 1)
        state.revealPending(); XCTAssertEqual(state.notes.map(\.id), ["005", "004", "003"])
        XCTAssertEqual(state.olderCursor, "003")
        state.page([note("003"), note("002")], older: true, preferences: p, accountID: "me")
        XCTAssertEqual(state.notes.count, 4); XCTAssertEqual(state.olderCursor, "002")
    }
    func testDeletionAlsoUpdatesQuotesAndNeverResurrects() {
        var state = TimelineState(); let p = TimelinePreferences()
        let target = note("001", ["text": .string("旧正文")])
        let quote = note("002", ["text": .string("引用"), "renote": target.raw])
        state.page([quote, target], older: false, preferences: p, accountID: "me")
        state.apply(.init(id: "001", kind: "deleted", body: .null), accountID: "me")
        XCTAssertEqual(state.notes.count, 1); XCTAssertTrue(state.notes[0]["renote"]["deleted"].bool)
        XCTAssertNil(state.notes[0]["renote"]["text"].string)
        state.page([target], older: true, preferences: p, accountID: "me"); XCTAssertEqual(state.notes.count, 1)
        state.page([quote], older: false, preferences: p, accountID: "me")
        XCTAssertNil(state.notes[0]["renote"]["text"].string, "A delayed page must not revive deleted quoted content")
        state.apply(.init(id: "001", kind: "replaced", body: target.raw), accountID: "me")
        XCTAssertTrue(state.notes[0]["renote"]["deleted"].bool)
    }
    func testReactionUpdateAndNestedSubscriptions() {
        let source = note("001", ["reactions": .object(["❤️": .number(1)])])
        let quote = note("002", ["text": .string("引用"), "renote": source.raw])
        let update = NoteStreamEvent(id: "001", kind: "reacted", body: .object(["userId": .string("me"), "reaction": .string("❤️")]))
        let result = update.applying(to: quote, accountID: "me")
        XCTAssertEqual(result["renote"]["reactions"]["❤️"].int, 2)
        XCTAssertEqual(result["renote"]["myReaction"].string, "❤️")
        XCTAssertEqual(result["renote"]["reactionCount"].int, 2)
        let duplicate = update.applying(to: result, accountID: "me")
        XCTAssertEqual(duplicate["renote"]["reactions"]["❤️"].int, 2, "An event after the user's API readback must not increment twice")
        XCTAssertEqual(TimelinePresentation.capturedIDs([quote]), ["001", "002"])
    }
    func testOlderPageIsNotDroppedAtFormerMemoryWindowBoundary() {
        var state = TimelineState(); let p = TimelinePreferences()
        let rows = (1...2000).reversed().map { note(String(format: "%06d", $0)) }
        state.page(rows, older: false, preferences: p, accountID: "me")
        state.page([note("000000")], older: true, preferences: p, accountID: "me")
        XCTAssertEqual(state.notes.last?.id, "000000"); XCTAssertEqual(state.notes.first?.id, "002000")
    }
}
