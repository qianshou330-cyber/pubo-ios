import XCTest
@testable import PUBOCore

final class AccountSettingsPolicyTests: XCTestCase {
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
