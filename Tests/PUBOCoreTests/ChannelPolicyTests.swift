import XCTest
@testable import PUBOCore

final class ChannelPolicyTests: XCTestCase {
    func testCreationRequiresExplicitAccountPolicy() {
        for value in [JSONValue.null, .bool(false), .string("true"), .number(1)] {
            XCTAssertFalse(ChannelPolicy.canCreate(user: .object(["policies": .object(["canCreateChannel": value])])))
        }
        XCTAssertFalse(ChannelPolicy.canCreate(user: .null))
        XCTAssertTrue(ChannelPolicy.canCreate(user: .object(["policies": .object(["canCreateChannel": .bool(true)])])))
    }
    func testCreationRestrictionDoesNotBlockExistingChannelEditsOrOtherCollections() {
        XCTAssertFalse(ChannelPolicy.canSave(kind: .channel, creating: true, user: .null))
        XCTAssertTrue(ChannelPolicy.canSave(kind: .channel, creating: false, user: .null))
        for kind in CollectionKind.allCases where kind != .channel {
            XCTAssertTrue(ChannelPolicy.canSave(kind: kind, creating: true, user: .null))
        }
    }
    func testBothSearchScopesHaveExactH5APIValuesAndTrimQuery() {
        XCTAssertEqual(ChannelSearchScope.nameAndDescription.request(query: "  music\n"), ["query": .string("music"), "type": .string("nameAndDescription")])
        XCTAssertEqual(ChannelSearchScope.nameOnly.request(query: "music")["type"], .string("nameOnly"))
        XCTAssertEqual(ChannelSearchScope.allCases.count, 2)
    }
}
