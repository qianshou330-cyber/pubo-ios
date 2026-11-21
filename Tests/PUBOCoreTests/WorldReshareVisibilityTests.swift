import XCTest
@testable import PUBOCore

final class WorldReshareVisibilityTests: XCTestCase {
    private let viewer = "syntheticself"
    private let other = "syntheticpeer"

    func testOpenPublicAndHomeRemainEligibleOnlyForSignedInViewer() {
        for visibility in ["public", "home"] {
            let row = note(visibility, author: other)
            XCTAssertTrue(WorldReshareVisibility.canShowMenu(row: row, viewerID: viewer))
            XCTAssertFalse(WorldReshareVisibility.canShowMenu(row: row, viewerID: nil))
        }
        XCTAssertFalse(allowed(note("public", author: other, id: "")))
    }

    func testFollowersRequiresExactCanonicalAuthorNotNestedUserFallback() {
        XCTAssertTrue(allowed(note("followers", author: viewer)))
        XCTAssertFalse(allowed(note("followers", author: other)))
        XCTAssertFalse(allowed(note("followers", author: "Syntheticself")))
        XCTAssertFalse(allowed(note("followers", author: viewer + " ")))
        XCTAssertFalse(allowed(Record(.object(["id": .string("a"), "visibility": .string("followers"),
            "user": .object(["id": .string(viewer)])]))))
        XCTAssertFalse(allowed(Record(.object(["id": .string("a"), "visibility": .string("followers"),
            "userId": .string(viewer), "user": .object(["id": .string(other)])]))))
    }

    func testSpecifiedUnknownAndHiddenTargetsNeverOfferTheMenu() {
        for author in [viewer, other] {
            for scope in ["specified", "", "public ", "PUBLIC", "unlisted"] {
                XCTAssertFalse(allowed(note(scope, author: author)), scope)
            }
        }
        XCTAssertFalse(allowed(note(nil, author: viewer)))
        XCTAssertFalse(allowed(Record(.object(["id": .string("a"), "visibility": .number(1)]))))
        XCTAssertFalse(allowed(Record(.object(["id": .string("a"), "visibility": .string("public"), "isHidden": .bool(true)]))))
    }

    func testPureRepostUsesDisplayedOriginalVisibilityAndAuthorNotWrapper() {
        XCTAssertFalse(allowed(wrapped(note("followers", author: other), wrapperScope: "public", wrapperAuthor: viewer)))
        XCTAssertTrue(allowed(wrapped(note("followers", author: viewer), wrapperScope: "public", wrapperAuthor: other)))
        XCTAssertFalse(allowed(wrapped(note("specified", author: viewer), wrapperScope: "public", wrapperAuthor: viewer)))
        XCTAssertTrue(allowed(wrapped(note("public", author: other), wrapperScope: "followers", wrapperAuthor: other)))
    }

    func testUnresolvedOrMismatchedRepostNeverFallsBackToPublicWrapper() {
        XCTAssertFalse(allowed(Record(.object(["id": .string("wrap"), "visibility": .string("public"), "renoteId": .string("missing")]))))
        XCTAssertFalse(allowed(wrapped(note("public", author: other), wrapperScope: "public", wrapperAuthor: viewer,
                                      declaredID: "different")))
        XCTAssertFalse(allowed(wrapped(note("public", author: other, id: "wrap"), wrapperScope: "public", wrapperAuthor: viewer)))
    }

    func testTextQuoteIsItsOwnTargetAndDoesNotUseNestedAuthorOrVisibility() {
        let nested = note("followers", author: other)
        XCTAssertTrue(allowed(wrapped(nested, wrapperScope: "home", wrapperAuthor: viewer, text: "Synthetic quote")))
        XCTAssertFalse(allowed(wrapped(note("public", author: viewer), wrapperScope: "followers", wrapperAuthor: other,
                                      text: "Synthetic quote")))
    }

    private func allowed(_ row: Record) -> Bool { WorldReshareVisibility.canShowMenu(row: row, viewerID: viewer) }

    private func note(_ visibility: String?, author: String, id: String = "original") -> Record {
        var data: [String: JSONValue] = ["id": .string(id), "userId": .string(author)]
        if let visibility { data["visibility"] = .string(visibility) }
        return Record(.object(data))
    }

    private func wrapped(_ original: Record, wrapperScope: String, wrapperAuthor: String,
                         declaredID: String? = nil, text: String = "") -> Record {
        Record(.object(["id": .string("wrap"), "visibility": .string(wrapperScope), "userId": .string(wrapperAuthor),
                        "renoteId": .string(declaredID ?? original.id), "renote": original.raw, "text": .string(text)]))
    }
}
