import XCTest
@testable import PUBOCore

final class RefreshTaskOwnerTests: XCTestCase {
    @MainActor
    func testCallbackCancellationDoesNotDiscardAnOwnedRefresh() async {
        let owner = RefreshTaskOwner()
        let started = expectation(description: "refresh started")
        let pair = AsyncStream<Void>.makeStream()
        var finished = false
        var cancelled = true
        let callback = Task {
            await owner.run {
                started.fulfill()
                for await _ in pair.stream { break }
                cancelled = Task.isCancelled
                finished = true
            }
        }
        await fulfillment(of: [started], timeout: 2)
        callback.cancel()
        pair.continuation.yield(())
        pair.continuation.finish()
        await callback.value
        XCTAssertTrue(finished)
        XCTAssertFalse(cancelled)
    }

    @MainActor
    func testScreenCancellationCancelsTheOwnedRefresh() async {
        let owner = RefreshTaskOwner()
        let started = expectation(description: "refresh started")
        let pair = AsyncStream<Void>.makeStream()
        var cancelled = false
        let callback = Task {
            await owner.run {
                started.fulfill()
                for await _ in pair.stream { break }
                cancelled = Task.isCancelled
            }
        }
        await fulfillment(of: [started], timeout: 2)
        owner.cancel()
        await callback.value
        pair.continuation.finish()
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testConcurrentRequestsCoalesceAndNextRefreshStillRuns() async {
        let owner = RefreshTaskOwner()
        let started = expectation(description: "first refresh started")
        let joining = expectation(description: "second caller joined")
        let pair = AsyncStream<Void>.makeStream()
        var count = 0
        let first = Task {
            await owner.run {
                count += 1; started.fulfill()
                for await _ in pair.stream { break }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joining.fulfill()
            await owner.run { count += 1 }
        }
        await fulfillment(of: [joining], timeout: 2)
        pair.continuation.yield(()); pair.continuation.finish()
        await first.value; await second.value
        XCTAssertEqual(count, 1)
        await owner.run { count += 1 }
        XCTAssertEqual(count, 2)
    }
}
