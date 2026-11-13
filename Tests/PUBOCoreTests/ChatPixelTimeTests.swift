import XCTest
@testable import PUBOCore

final class ChatPixelTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ seconds: Double) -> String {
        ChatRelativeTimePolicy.label(date: now.addingTimeInterval(-seconds), now: now)
    }
    func testWeekThresholdAndHalfWeekRounding() {
        XCTAssertEqual(ago(7 * 86_400 - 1), "7天前")
        XCTAssertEqual(ago(7 * 86_400), "1周前")
        XCTAssertEqual(ago(10.5 * 86_400 - 1), "1周前")
        XCTAssertEqual(ago(10.5 * 86_400), "2周前")
        XCTAssertEqual(ago(11 * 86_400), "2周前")
    }
    func testMinuteTruncationAndOtherPastBoundaries() {
        XCTAssertEqual(ago(9.99), "刚刚")
        XCTAssertEqual(ago(10), "10秒前")
        XCTAssertEqual(ago(59.9), "59秒前")
        XCTAssertEqual(ago(60), "1分钟前")
        XCTAssertEqual(ago(119.9), "1分钟前")
        XCTAssertEqual(ago(3_599), "59分钟前")
        XCTAssertEqual(ago(3_600), "1小时前")
        XCTAssertEqual(ago(5_400), "2小时前")
        XCTAssertEqual(ago(86_400), "1天前")
        XCTAssertEqual(ago(2_592_000), "1个月前")
        XCTAssertEqual(ago(31_536_000), "1年前")
    }
    func testFutureUsesH5StrictThresholdsAndInvalidPolicy() {
        XCTAssertEqual(ago(-3), "刚刚")
        XCTAssertEqual(ago(-4), "4秒后")
        // Preserve the snapshot's exact-minute quirk, rather than silently changing policy.
        XCTAssertEqual(ago(-60), "0秒后")
        XCTAssertEqual(ago(-61), "1分钟后")
        XCTAssertEqual(ago(-3_600), "60分钟后")
        XCTAssertEqual(ago(-3_601), "1小时后")
        XCTAssertEqual(ago(-604_800), "7天后")
        XCTAssertEqual(ago(-604_801), "1周后")
        XCTAssertEqual(ago(-10.5 * 86_400), "2周后")
        XCTAssertEqual(ChatRelativeTimePolicy.label(date: nil, now: now), "没有")
        XCTAssertEqual(ChatRelativeTimePolicy.label(date: Date(timeIntervalSince1970: .nan), now: now), "没有")
    }
    private func message(_ date: String) -> Record { Record(.object(["createdAt": .string(date)])) }
    func testStructuredBoundaryOrderingAndTimezone() throws {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let before = message("2026-11-02T23:30:00Z"), after = message("2026-11-03T00:30:00Z")
        let pair = try XCTUnwrap(ChatDays.pair(previous: before, current: after, calendar: utc))
        XCTAssertEqual(pair.older, "11/2"); XCTAssertEqual(pair.newer, "11/3")
        XCTAssertEqual(pair.privateText, "11/3 · 11/2")
        XCTAssertEqual(pair.chronologicalText, "11/2 · 11/3")
        var east = utc; east.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        XCTAssertNil(ChatDays.pair(previous: before, current: after, calendar: east))
        XCTAssertNil(ChatDays.pair(previous: nil, current: after, calendar: utc))
        XCTAssertNil(ChatDays.pair(previous: message("invalid"), current: after, calendar: utc))
    }
    func testCrossYearRetainsNativeYearEnhancement() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let pair = try XCTUnwrap(ChatDays.pair(previous: message("2026-12-31T15:59:00Z"), current: message("2026-12-31T16:01:00Z"), calendar: calendar))
        XCTAssertEqual(pair.privateText, "2027/1/1 · 2026/12/31")
        XCTAssertEqual(pair.chronologicalText, "2026/12/31 · 2027/1/1")
    }
}
