import XCTest
@testable import PUBOCore

final class FollowActionTests: XCTestCase {
    private func user(following: Bool = false, pending: Bool = false, locked: Bool = false) -> Record {
        Record(.object(["isFollowing": .bool(following), "hasPendingFollowRequestFromYou": .bool(pending), "isLocked": .bool(locked)]))
    }
    func testFollowAndLockedRequestUseCreateWithoutRemovalConfirmation() {
        XCTAssertEqual(ProfileFollowAction(user: user()), .follow)
        XCTAssertEqual(ProfileFollowAction(user: user(locked: true)), .request)
        XCTAssertEqual(ProfileFollowAction.request.endpoint, "following/create")
        XCTAssertFalse(ProfileFollowAction.follow.requiresConfirmation)
        XCTAssertFalse(ProfileFollowAction.request.requiresConfirmation)
    }
    func testPendingRequestNeverCreatesAgain() {
        for locked in [true, false] {
            let action = ProfileFollowAction(user: user(pending: true, locked: locked))
            XCTAssertEqual(action, .cancelRequest)
            XCTAssertEqual(action.endpoint, "following/requests/cancel")
            XCTAssertTrue(action.requiresConfirmation)
        }
    }
    func testFollowingTakesPrecedenceAndRequiresConfirmation() {
        let action = ProfileFollowAction(user: user(following: true, pending: true))
        XCTAssertEqual(action, .unfollow)
        XCTAssertEqual(action.endpoint, "following/delete")
        XCTAssertTrue(action.requiresConfirmation)
    }
    func testGalleryFeaturedAndPopularShareNonPaginatedEndpoint() {
        for mode in ["featured", "popular"] {
            XCTAssertEqual(CollectionListing.endpoint(kind: .gallery, mode: mode), "gallery/featured")
            XCTAssertFalse(CollectionListing.paginated(kind: .gallery, mode: mode))
        }
        XCTAssertEqual(CollectionListing.endpoint(kind: .gallery, mode: "latest"), "gallery/posts")
        XCTAssertTrue(CollectionListing.paginated(kind: .gallery, mode: "latest"))
        XCTAssertTrue(CollectionListing.paginated(kind: .gallery, mode: "mine"))
    }
    func testFavoriteClipsAreNotPaginated() {
        XCTAssertEqual(CollectionListing.endpoint(kind: .clip, mode: "favorites"), "clips/my-favorites")
        XCTAssertFalse(CollectionListing.paginated(kind: .clip, mode: "favorites"))
        XCTAssertEqual(CollectionListing.endpoint(kind: .clip, mode: "mine"), "clips/list")
        XCTAssertTrue(CollectionListing.paginated(kind: .clip, mode: "mine"))
    }
}
