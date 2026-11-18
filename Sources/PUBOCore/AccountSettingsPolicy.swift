import Foundation

/// Dependencies mirror the H5 privacy/email controls. Disabled controls keep
/// their stored values; changing a parent setting must not erase preferences.
public enum AccountSettingsPolicy {
    public static func canEditPrivacyOption(_ key: String, values: [String: JSONValue], loaded: Bool, busy: Bool) -> Bool {
        guard loaded, !busy else { return false }
        return key != "autoAcceptFollowed" || values["isLocked"] == .bool(true)
    }
    /// Rebase only after a successful read-back. Keep the original editable key
    /// set; unrelated account fields must never become a future update payload.
    public static func confirmedPrivacyDraft(_ confirmed: JSONValue, editableKeys: [String]) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: Set(editableKeys).map { ($0, confirmed[$0]) })
    }
    public static func emailAvailable(meta: JSONValue) -> Bool {
        meta["enableEmail"] == .bool(true)
    }
}
