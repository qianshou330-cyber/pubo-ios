import XCTest
@testable import PUBOCore

final class WorldTimelinePolicyTests: XCTestCase {
    private func user(local: Bool) -> JSONValue {
        .object(["id": .string("fixture-user"), "policies": .object(["ltlAvailable": .bool(local), "gtlAvailable": .bool(true)])])
    }
    func testOnlyApprovedWorldSections() {
        XCTAssertEqual(WorldTimelinePolicy.choices(user: user(local: true)), ["local", "home"])
        XCTAssertEqual(WorldTimelinePolicy.title(for: "local"), "推荐")
        XCTAssertEqual(WorldTimelinePolicy.title(for: "home"), "关注")
        XCTAssertEqual(WorldTimelinePolicy.choices(user: .null), [])
    }
    func testOldHybridOrGlobalSelectionMigratesToPublicFeed() {
        for old in ["hybrid", "global", "unknown"] {
            var value = TimelinePreferences(); value.selected = old
            WorldTimelinePolicy.normalize(&value, user: user(local: true))
            XCTAssertEqual(value.selected, "local")
        }
    }
    func testPermissionLossFallsBackWithoutInventingRecommendations() {
        var value = TimelinePreferences(); value.selected = "local"
        WorldTimelinePolicy.normalize(&value, user: user(local: false))
        XCTAssertEqual(value.selected, "home")
        XCTAssertEqual(WorldTimelinePolicy.choices(user: user(local: false)), ["home"])
    }
    func testMediaOnlyDoesNotRestoreConflictingRepliesFilter() {
        var value = TimelinePreferences(); value.onlyFiles = true; value.withReplies = true
        WorldTimelinePolicy.normalize(&value, user: user(local: true))
        XCTAssertTrue(value.onlyFiles); XCTAssertFalse(value.withReplies)
    }
    func testFollowChoiceAndOtherPreferencesSurviveMigration() {
        var value = TimelinePreferences(); value.selected = "home"; value.withRenotes = false; value.fixedComposer = true
        WorldTimelinePolicy.normalize(&value, user: user(local: true))
        XCTAssertEqual(value.selected, "home"); XCTAssertFalse(value.withRenotes); XCTAssertTrue(value.fixedComposer)
    }
}
