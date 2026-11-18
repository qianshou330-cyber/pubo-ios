import XCTest
@testable import PUBOCore

final class LoadRequestOwnershipTests: XCTestCase {
    func testNormalCompletionAndDuplicateStart() throws {
        var owner = LoadRequestOwnership()
        let request = try XCTUnwrap(owner.begin())
        XCTAssertTrue(owner.isLoading)
        XCTAssertNil(owner.begin())
        owner.finish(request)
        XCTAssertFalse(owner.isLoading)
    }
    func testOldCompletionCannotReleaseReappearedRequest() throws {
        var owner = LoadRequestOwnership()
        let old = try XCTUnwrap(owner.begin())
        owner.invalidate()
        XCTAssertFalse(owner.isLoading)
        let fresh = try XCTUnwrap(owner.begin())
        owner.finish(old)
        XCTAssertTrue(owner.isLoading)
        XCTAssertNil(owner.begin())
        owner.finish(fresh)
        XCTAssertFalse(owner.isLoading)
    }
    func testNewCompletionBeforeOldAndRepeatedInvalidation() throws {
        var owner = LoadRequestOwnership()
        let old = try XCTUnwrap(owner.begin())
        owner.invalidate(); owner.invalidate()
        let fresh = try XCTUnwrap(owner.begin())
        owner.finish(fresh); owner.finish(old)
        XCTAssertFalse(owner.isLoading)
        XCTAssertNotNil(owner.begin())
    }
    func testContentEpochChangesDoNotOwnRequestRelease() throws {
        var owner = LoadRequestOwnership()
        var contentEpoch = UUID()
        let epoch = contentEpoch
        let request = try XCTUnwrap(owner.begin())
        contentEpoch = UUID()
        XCTAssertNotEqual(epoch, contentEpoch)
        // A stale content response must still release its own busy indicator.
        owner.finish(request)
        XCTAssertFalse(owner.isLoading)
    }
    func testTimelineAndContextHaveSeparateOwnership() throws {
        var timeline = LoadRequestOwnership(), context = LoadRequestOwnership()
        let a = try XCTUnwrap(timeline.begin()), b = try XCTUnwrap(context.begin())
        timeline.invalidate()
        XCTAssertTrue(context.isLoading)
        timeline.finish(a); context.finish(b)
        XCTAssertFalse(timeline.isLoading); XCTAssertFalse(context.isLoading)
    }
}
