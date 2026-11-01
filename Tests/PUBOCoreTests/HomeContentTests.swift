import XCTest
@testable import PUBOCore

final class HomeContentTests: XCTestCase {
    func testTimelineChoicesDoNotInventPermissions() {
        XCTAssertEqual(HomeContent.timelines(user: .null), [])
        XCTAssertEqual(HomeContent.timelines(user: .object(["id": .string("u")])), ["home"])
        XCTAssertEqual(HomeContent.timelines(user: .object(["id": .string("u"), "policies": .object(["ltlAvailable": .bool(true), "gtlAvailable": .bool(false)])])), ["home", "local", "hybrid"])
    }
    func testChartRowsRetainOfficialRanksAndDeduplicateSongs() {
        func row(_ id: String, _ rank: Int, group: Bool = true) -> JSONValue { .object(["songId": .string(id), "rank": .number(Double(rank)), "groupIds": .strings(group ? ["a2o-lite"] : [])]) }
        let data = JSONValue.object(["entries": .array([row("b", 12), row("a", 4), row("a", 4), row("unrelated", 1, group: false), row("invalid", 0)])])
        XCTAssertEqual(HomeContent.chartRows(data, limit: 2).map { $0["rank"].int }, [4, 12])
        XCTAssertTrue(HomeContent.chartScope(.object(["rankBasis": .string("playlist_order")])).contains("非官方排名"))
    }
    func testAnnouncementsExcludeTargetedAndNormalItems() {
        let entries = ["public", "targeted", "normal"].map { id in Record(.object(["id": .string(id), "display": .string(id == "normal" ? "normal" : "marquee"), "forYou": .bool(id == "targeted")])) }
        XCTAssertEqual(HomeContent.publicAnnouncements(entries).map(\.id), ["public"])
    }
}
