import Foundation

/// Sensitivity controls disclosure, not permanent eligibility. Never change the
/// server's sensitive flag merely because someone previews or selects a file.
public enum DriveMediaPolicy {
    public static func requiresConfirmation(isSensitive: Bool) -> Bool { isSensitive }
    public static func canSelect(mime: String, imagesOnly: Bool) -> Bool {
        !imagesOnly || mime.hasPrefix("image/")
    }
}
