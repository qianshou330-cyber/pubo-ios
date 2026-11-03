import XCTest
@testable import PUBOCore

final class ChartRefreshTests: XCTestCase {
    private func data(_ ranks: [(String, Int)], key: String = "melon-top100", status: String = "available") -> JSONValue {
        .object(["selected": .object(["chartKey": .string(key), "status": .string(status)]), "entries": .array(ranks.map { .object(["songId": .string($0.0), "rank": .number(Double($0.1)), "groupIds": .strings(["aespa"]), "sourceMovement": .object(["type": .string("same")])]) })])
    }
    func testRefreshUsesStableIdentityAndActualRanksNotSourceMovement() {
        let result = ChartRefresh.changes(previous: data([("a", 5), ("b", 2)]), incoming: data([("a", 1), ("b", 6), ("new", 3)]))
        XCTAssertEqual(result["a"]?.from, 5); XCTAssertEqual(result["a"]?.to, 1)
        XCTAssertEqual(result["a"]?.offset, -6); XCTAssertEqual(result["b"]?.offset, 6)
        XCTAssertNil(result["new"])
    }
    func testNoAnimationForInitialStaleOrDifferentContext() {
        let old = data([("a", 5)]), new = data([("a", 1)])
        XCTAssertTrue(ChartRefresh.changes(previous: .null, incoming: new).isEmpty)
        XCTAssertTrue(ChartRefresh.changes(previous: old, incoming: old).isEmpty)
        XCTAssertTrue(ChartRefresh.changes(previous: old, incoming: new, contextMatches: false).isEmpty)
        XCTAssertTrue(ChartRefresh.changes(previous: old, incoming: data([("a", 1)], key: "genie-realtime")).isEmpty)
        XCTAssertTrue(ChartRefresh.changes(previous: old, incoming: data([("a", 1)], status: "stale")).isEmpty)
    }
    func testKoreanTimeIsExplicitAcrossMidnightAndInvalidDates() {
        XCTAssertEqual(ChartClock.korean("2026-11-01T15:30:00Z"), "2026-11-02 00:30 KST")
        XCTAssertNil(ChartClock.korean("not a date"))
        XCTAssertNil(ChartClock.korean(nil))
    }
}
