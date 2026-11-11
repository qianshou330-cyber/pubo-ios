import Foundation

/// Dependencies mirror the H5 privacy/email controls. Disabled controls keep
/// their stored values; changing a parent setting must not erase preferences.
public enum AccountSettingsPolicy {
    public static func canEditPrivacyOption(_ key: String, values: [String: JSONValue], loaded: Bool, busy: Bool) -> Bool {
        guard loaded, !busy else { return false }
        return key != "autoAcceptFollowed" || values["isLocked"] == .bool(true)
    }
    public static func emailAvailable(meta: JSONValue) -> Bool {
        meta["enableEmail"] == .bool(true)
    }
}
