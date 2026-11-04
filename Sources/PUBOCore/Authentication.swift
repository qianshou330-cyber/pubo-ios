import Foundation

/// Matches MkSignupDialog.form.vue. Strength is a hint, never an acceptance rule.
public enum AuthenticationInput {
    public static func phone(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression)
        return compact.hasPrefix("+86") ? String(compact.dropFirst(3)) : compact
    }
    public static func validPhone(_ value: String) -> Bool { matches(phone(value), "^1[3-9][0-9]{9}$") }
    public static func validUsername(_ value: String, signup: Bool = false) -> Bool {
        matches(value, signup ? "^[A-Za-z0-9_]{1,20}$" : "^[A-Za-z0-9_]+$")
    }
    public static func validCode(_ value: String, backup: Bool = false) -> Bool {
        matches(value, backup ? "^[A-Z0-9]{32}$" : "^[0-9]{6}$")
    }
    public static func passwordStrength(_ value: String) -> Double {
        var power = 0.018
        if matches(value, "[a-zA-Z]") && matches(value, "[0-9]") { power += 0.020 }
        if matches(value, "[a-z]") && matches(value, "[A-Z]") { power += 0.015 }
        if value.contains(where: { "!\"#$%&@'()*+,-./_".contains($0) }) { power += 0.020 }
        return min(1, max(0, power * Double(value.utf16.count)))
    }
    public static func strengthLabel(_ value: String) -> String {
        let strength = passwordStrength(value)
        return strength > 0.7 ? "密码强度：强" : strength > 0.3 ? "密码强度：中" : "密码强度：弱"
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

public enum SigninNext: Equatable, Sendable {
    case password(captcha: Bool), totp, passkey, finished(String)
    public init(_ value: JSONValue) throws {
        if value["finished"].bool {
            guard let token = value["i"].string, !token.isEmpty else { throw APIError.invalidResponse }
            self = .finished(token); return
        }
        switch value["next"].string {
        case "password": self = .password(captcha: false)
        case "captcha": self = .password(captcha: true)
        case "totp": self = .totp
        case "passkey": self = .passkey
        default: throw APIError.invalidResponse
        }
    }
}

public enum AccountAvailability: Equatable, Sendable {
    case idle, checking, available, unavailable(String), failed
    public var accepted: Bool { self == .available }
    public var label: String {
        switch self {
        case .idle: return ""
        case .checking: return "正在检查…"
        case .available: return "可以使用"
        case .unavailable(let reason): return reason
        case .failed: return "检查失败，请重试"
        }
    }
    public static func email(_ response: JSONValue) throws -> Self {
        guard case .bool(let available) = response["available"] else { throw APIError.invalidResponse }
        if available { return .available }
        let reasons = ["used": "邮箱已被使用", "format": "邮箱格式不正确", "disposable": "不支持临时邮箱", "banned": "不支持此邮箱", "mx": "邮箱域名不可用", "smtp": "无法确认此邮箱"]
        return .unavailable(reasons[response["reason"].string ?? ""] ?? "邮箱暂不可用")
    }
}
