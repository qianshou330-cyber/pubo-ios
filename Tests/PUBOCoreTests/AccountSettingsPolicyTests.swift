import XCTest
@testable import PUBOCore

final class AccountSettingsPolicyTests: XCTestCase {
    func testConfirmedPrivacyDraftDoesNotRevertUntouchedRemoteChange() {
        let confirmed: JSONValue = .object(["isLocked": .bool(true), "hideOnlineStatus": .bool(true), "name": .string("not editable here")])
        let draft = AccountSettingsPolicy.confirmedPrivacyDraft(confirmed, editableKeys: ["isLocked", "hideOnlineStatus"])
        XCTAssertEqual(draft["isLocked"], .bool(true))
        XCTAssertEqual(draft["hideOnlineStatus"], .bool(true))
        XCTAssertNil(draft["name"])
        XCTAssertTrue(draft.filter { confirmed[$0.key] != $0.value }.isEmpty)
        var next = draft
        next["isLocked"] = .bool(false)
        XCTAssertEqual(Set(next.filter { confirmed[$0.key] != $0.value }.keys), ["isLocked"])
    }
    func testConfirmedPrivacyDraftRetainsDisabledPreferenceAndMissingKeys() {
        let confirmed: JSONValue = .object(["isLocked": .bool(false), "autoAcceptFollowed": .bool(true)])
        let draft = AccountSettingsPolicy.confirmedPrivacyDraft(confirmed, editableKeys: ["isLocked", "autoAcceptFollowed", "followingVisibility", "isLocked"])
        XCTAssertEqual(draft["autoAcceptFollowed"], .bool(true))
        XCTAssertEqual(draft["followingVisibility"], .null)
        XCTAssertEqual(draft.count, 3)
    }
    func testAutoAcceptRequiresLockedAccount() {
        for locked in [false, true] {
            XCTAssertEqual(AccountSettingsPolicy.canEditPrivacyOption("autoAcceptFollowed", values: ["isLocked": .bool(locked)], loaded: true, busy: false), locked)
        }
        XCTAssertFalse(AccountSettingsPolicy.canEditPrivacyOption("autoAcceptFollowed", values: [:], loaded: true, busy: false))
    }
    func testLoadingAndSavingDisableAllPrivacyControls() {
        for key in ["isLocked", "autoAcceptFollowed", "publicReactions"] {
            XCTAssertFalse(AccountSettingsPolicy.canEditPrivacyOption(key, values: ["isLocked": .bool(true)], loaded: false, busy: false))
            XCTAssertFalse(AccountSettingsPolicy.canEditPrivacyOption(key, values: ["isLocked": .bool(true)], loaded: true, busy: true))
        }
    }
    func testUnlockingDoesNotEraseAutoAcceptPreference() {
        var values: [String: JSONValue] = ["isLocked": .bool(true), "autoAcceptFollowed": .bool(true)]
        values["isLocked"] = .bool(false)
        XCTAssertFalse(AccountSettingsPolicy.canEditPrivacyOption("autoAcceptFollowed", values: values, loaded: true, busy: false))
        XCTAssertEqual(values["autoAcceptFollowed"], .bool(true))
        XCTAssertTrue(AccountSettingsPolicy.canEditPrivacyOption("isLocked", values: values, loaded: true, busy: false))
    }
    func testEmailRequiresExplicitServerCapability() {
        XCTAssertTrue(AccountSettingsPolicy.emailAvailable(meta: .object(["enableEmail": .bool(true)])))
        let unavailable: [JSONValue] = [.null, .object([:]), .object(["enableEmail": .bool(false)]), .object(["enableEmail": .string("true")])]
        for meta in unavailable {
            XCTAssertFalse(AccountSettingsPolicy.emailAvailable(meta: meta))
        }
    }
}
