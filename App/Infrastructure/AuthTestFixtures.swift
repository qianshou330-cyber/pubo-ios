#if DEBUG
import Foundation
import PUBOCore

/// Deterministic, synthetic-only UI responses. Never falls through to a network.
enum AuthTestFixtures {
    static func response(path: String, body: JSONValue, args: [String]) async throws -> (JSONValue, Int)? {
        guard args.contains("--auth-static") else { return nil }
        func failure(_ code: String, status: Int = 400) -> (JSONValue, Int) { (.object(["error": .object(["code": .string(code)])]), status) }
        switch path {
        case "meta":
            return (.object(["name": .string("PUBO"), "enableEmail": .bool(true), "disableRegistration": .bool(args.contains("--auth-restricted")), "emailRequiredForSignup": .bool(args.contains("--auth-email")), "enableTurnstile": .bool(args.contains("--auth-captcha")), "serverRules": args.contains("--auth-restricted") ? .strings(["请尊重他人并保护隐私。", "请勿发送垃圾信息。"]) : .array([])]), 200)
        case "username/available", "email-address/available":
            let value = body[path == "username/available" ? "username" : "emailAddress"].string ?? ""
            if value.hasPrefix("slow") { try? await Task.sleep(for: .seconds(3)) }
            if value.hasPrefix("failed") { throw URLError(.timedOut) }
            return (.object(["available": .bool(!value.hasPrefix("taken") && !value.hasPrefix("slow")), "reason": .string("used")]), 200)
        case "signin-flow":
            if args.contains("--auth-slow-login") { try? await Task.sleep(for: .seconds(4)) }
            if body["username"].string == "limited" { return failure("TOO_MANY_AUTHENTICATION_FAILURES", status: 429) }
            if body["username"].string == "missing" { return failure("SIGNIN_NO_USER", status: 404) }
            if body["password"].isNull { return (.object(["next": .string("password")]), 200) }
            if body["password"].string == "wrong" { return failure("SIGNIN_PASSWORD", status: 403) }
            if args.contains("--auth-totp") && body["token"].isNull { return (.object(["next": .string("totp")]), 200) }
            if body["token"].string == "000000" { return failure("SIGNIN_OTP", status: 403) }
            return (.object(["finished": .bool(true), "i": .string("synthetic-session")]), 200)
        case "signup/request-phone-code", "request-reset-password-phone":
            if args.contains("--auth-sms-timeout") { throw URLError(.timedOut) }
            if args.contains("--auth-sms-failed") { return failure("SMS_SEND_FAILED") }
            guard AuthenticationInput.validPhone(body["phoneNumber"].string ?? ""), !(body["phoneNumber"].string ?? "").contains(" ") else { return failure("INVALID_PHONE_NUMBER") }
            return (.null, 204)
        case "signup": return args.contains("--auth-email") ? (.null, 204) : (.object(["token": .string("synthetic-session")]), 200)
        case "request-reset-password": return (.null, 204)
        case "reset-password-phone": return body["smsCode"].string == "000000" ? failure("INVALID_SMS_CODE") : (.null, 204)
        default: return nil
        }
    }
}
#endif
