import XCTest
@testable import PUBOCore

final class TimelineCaptureLookupTests: XCTestCase {
    private func note(_ id: String, child: String? = nil) -> Record {
        var fields: [String: JSONValue] = ["id": .string(id), "text": .string("synthetic wrapper")]
        if let child { fields["renote"] = .object(["id": .string(child), "reply": .object(["id": .string(child + "-reply")])]) }
        return Record(.object(fields))
    }
    private func verify(_ state: TimelineState, _ visible: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        for records in [state.notes, state.pending] {
            let ids = records.map(\.id)
            XCTAssertEqual(ids, ids.sorted(by: >), file: file, line: line)
            XCTAssertEqual(Set(ids).count, ids.count, file: file, line: line)
        }
        let oracle = TimelinePresentation.capturedIDs(state.notes.filter { visible.contains($0.id) })
        XCTAssertEqual(state.experimentalCapturedIDs(visibleIDs: visible), oracle, file: file, line: line)
        let reversed = Array(state.notes.reversed()).filter { visible.contains($0.id) }
        XCTAssertEqual(oracle, TimelinePresentation.capturedIDs(reversed), file: file, line: line)
    }
    func testLexicalEmptyUnknownDuplicateVisibleAndBothPageDirections() {
        var state = TimelineState(); let p = TimelinePreferences()
        let ids = ["2", "10", "a", "A", "é", "z", "01", "001"]
        state.page(ids.map { note($0, child: "nested-" + $0) }, older: false, preferences: p, accountID: nil)
        verify(state, Set(ids + ids + ["unknown", ""]))
        verify(state, [])
        state.page([note("0"), note("2", child: "replacement"), note("")], older: true, preferences: p, accountID: nil)
        verify(state, ["0", "2", "removed", ""])
        XCTAssertTrue(state.experimentalCapturedIDs(visibleIDs: ["2"]).contains("replacement"))
        XCTAssertFalse(state.experimentalCapturedIDs(visibleIDs: ["2"]).contains("nested-2"))
    }
    func testSameIDNestedReplacementDeletionAndStalePages() {
        var state = TimelineState(); let p = TimelinePreferences()
        let old = note("wrapper", child: "old")
        state.page([old, note("standalone")], older: false, preferences: p, accountID: "me")
        state.apply(.init(id: "wrapper", kind: "replaced", body: note("wrapper", child: "new").raw), accountID: "me")
        verify(state, ["wrapper", "standalone"])
        XCTAssertEqual(state.experimentalCapturedIDs(visibleIDs: ["wrapper"]), ["wrapper", "new", "new-reply"])
        state.apply(.init(id: "new", kind: "replaced", body: note("new", child: "deep").raw), accountID: "me")
        verify(state, ["wrapper"])
        XCTAssertFalse(state.experimentalCapturedIDs(visibleIDs: ["wrapper"]).contains("new-reply"))
        state.apply(.init(id: "new", kind: "deleted", body: .null), accountID: "me")
        state.page([note("wrapper", child: "new")], older: true, preferences: p, accountID: "me")
        verify(state, ["wrapper"])
        XCTAssertEqual(state.experimentalCapturedIDs(visibleIDs: ["wrapper"]), ["wrapper", "new"])
        state.apply(.init(id: "wrapper", kind: "deleted", body: .null), accountID: "me")
        state.page([old], older: false, preferences: p, accountID: "me")
        state.apply(.init(id: "wrapper", kind: "replaced", body: old.raw), accountID: "me")
        verify(state, ["wrapper", "standalone"])
        XCTAssertEqual(state.experimentalCapturedIDs(visibleIDs: ["wrapper"]), [])
    }
    func testPendingNotCapturedUntilRevealAndResetDropsOldVisibleIDs() {
        var state = TimelineState(); let p = TimelinePreferences()
        state.receive(note("a", child: "shared"), atTop: true, preferences: p, accountID: nil)
        state.receive(note("z", child: "shared"), atTop: false, preferences: p, accountID: nil)
        state.receive(note("z", child: "latest"), atTop: false, preferences: p, accountID: nil)
        verify(state, ["a", "z"])
        XCTAssertFalse(state.experimentalCapturedIDs(visibleIDs: ["z"]).contains("latest"))
        state.revealPending(); verify(state, ["a", "z"])
        XCTAssertTrue(state.experimentalCapturedIDs(visibleIDs: ["z"]).contains("latest"))
        state.receive(note("z", child: "newer"), atTop: false, preferences: p, accountID: nil)
        verify(state, ["z"])
        XCTAssertFalse(state.experimentalCapturedIDs(visibleIDs: ["z"]).contains("latest"))
        state.reset(); verify(state, ["a", "z"])
        state.page([note("a", child: "fresh")], older: false, preferences: p, accountID: nil)
        XCTAssertEqual(state.experimentalCapturedIDs(visibleIDs: ["a", "z"]), ["a", "fresh", "fresh-reply"])
    }
    func testBoundedDepthSharedReferencesAndRepostRemoval() {
        func nested(_ depth: Int) -> JSONValue {
            var fields: [String: JSONValue] = ["id": .string("depth\(depth)")]
            if depth < 5 { fields["reply"] = nested(depth + 1) }
            return .object(fields)
        }
        var state = TimelineState(); let p = TimelinePreferences()
        state.page([Record(nested(0)), note("wrapper", child: "depth1"), Record(.object(["id": .string("repost"), "renote": note("target").raw]))], older: false, preferences: p, accountID: nil)
        verify(state, Set(state.notes.map(\.id)))
        XCTAssertEqual(state.experimentalCapturedIDs(visibleIDs: ["depth0"]), ["depth0", "depth1", "depth2", "depth3"])
        state.apply(.init(id: "target", kind: "deleted", body: .null), accountID: nil)
        verify(state, ["repost", "depth0", "wrapper"])
        XCTAssertFalse(state.notes.contains { $0.id == "repost" })
    }
    func testSeededMutationSequenceMatchesFilterAfterEveryWrite() {
        var seed: UInt64 = 0xC78020261119
        func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
        var state = TimelineState(); let p = TimelinePreferences()
        for step in 0..<400 {
            let id = "id-\(next() % 37)", child = "child-\(next() % 19)"
            let row = note(id, child: child)
            switch step % 8 {
            case 0: state.page([row, note("id-\(next() % 37)")], older: false, preferences: p, accountID: "me")
            case 1: state.page([row], older: true, preferences: p, accountID: "me")
            case 2: state.receive(row, atTop: true, preferences: p, accountID: "me")
            case 3: state.receive(row, atTop: false, preferences: p, accountID: "me")
            case 4: state.revealPending()
            case 5: state.apply(.init(id: id, kind: "replaced", body: row.raw), accountID: "me")
            case 6: state.apply(.init(id: step % 3 == 0 ? child : id, kind: "deleted", body: .null), accountID: "me")
            default:
                if step % 31 == 0 { state.reset() }
                else { state.apply(.init(id: child, kind: "reacted", body: .object(["userId": .string("other"), "reaction": .string("heart")])), accountID: "me") }
            }
            var visible = Set((0..<8).map { _ in "id-\(next() % 37)" }); visible.insert("unknown")
            verify(state, visible)
            verify(state, Set(state.notes.map(\.id)))
            verify(state, [])
        }
    }
    func testHistoricalRowsBeyond2000StaySearchable() {
        var state = TimelineState(); let p = TimelinePreferences()
        state.page((0..<2000).map { note(String(format: "%06d", $0)) }, older: false, preferences: p, accountID: nil)
        state.page([note("-old", child: "historical")], older: true, preferences: p, accountID: nil)
        verify(state, ["-old", "000000", "001999", "absent"])
        XCTAssertTrue(state.experimentalCapturedIDs(visibleIDs: ["-old"]).contains("historical"))
    }
}
