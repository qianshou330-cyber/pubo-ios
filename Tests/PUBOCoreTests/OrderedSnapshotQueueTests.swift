import XCTest
@testable import PUBOCore

final class OrderedSnapshotQueueTests: XCTestCase {
    func testSnapshotRunsOffCallerAndDeletionWins() {
        let queue = OrderedSnapshotQueue()
        var file: String?
        queue.submit(key: "a:timeline") { XCTAssertFalse(Thread.isMainThread); file = "old" }
        queue.sync { file = nil }
        queue.sync { XCTAssertNil(file) }
    }
    func testCancelAndCoalesceWhileWriterBusy() {
        let queue = OrderedSnapshotQueue()
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        var values = [String]()
        queue.submit(key: "busy") { entered.signal(); _ = release.wait(timeout: .now() + 5) }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        queue.submit(key: "a") { values.append("stale-account") }
        queue.cancelPending()
        queue.submit(key: "b") { values.append("old-page") }
        queue.submit(key: "b") { values.append("latest-page") }
        release.signal()
        queue.sync { XCTAssertEqual(values, ["latest-page"]) }
    }
    func testSeparateAccountsDoNotCoalesceEachOther() {
        let queue = OrderedSnapshotQueue()
        var values = [String]()
        queue.submit(key: "a:timeline") { values.append("a") }
        queue.submit(key: "b:timeline") { values.append("b") }
        queue.sync { XCTAssertEqual(values, ["a", "b"]) }
    }
}
