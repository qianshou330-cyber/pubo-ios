import XCTest
@testable import PUBOCore

final class AuthenticationTests: XCTestCase {
    func testPhoneNormalizationMatchesWebsite() {
        for input in ["19900000001", "+86 199-0000-0001", " 199\t0000 0001 "] { XCTAssertEqual(AuthenticationInput.phone(input), "19900000001"); XCTAssertTrue(AuthenticationInput.validPhone(input)) }
        for input in ["+1 19900000001", "8619900000001", "1990000000", "12900000001"] { XCTAssertFalse(AuthenticationInput.validPhone(input)) }
    }
    func testPasswordHintMatchesH5WithoutImposingThreshold() {
        XCTAssertEqual(AuthenticationInput.passwordStrength("abcd"), 0.072, accuracy: 0.000001)
        XCTAssertEqual(AuthenticationInput.passwordStrength("aA1!"), 0.292, accuracy: 0.000001)
        XCTAssertEqual(AuthenticationInput.passwordStrength("aA1!abcd"), 0.584, accuracy: 0.000001)
        XCTAssertEqual(AuthenticationInput.passwordStrength("😀"), 0.036, accuracy: 0.000001)
        XCTAssertEqual(AuthenticationInput.passwordStrength(String(repeating: "aA1!", count: 20)), 1)
        XCTAssertEqual(AuthenticationInput.strengthLabel("aA1!"), "密码强度：弱")
        XCTAssertEqual(AuthenticationInput.strengthLabel("aA1!abcd"), "密码强度：中")
    }
    func testSignupUsernameLimitDoesNotBlockLegacyLogin() {
        XCTAssertTrue(AuthenticationInput.validUsername(String(repeating: "a", count: 21)))
        XCTAssertFalse(AuthenticationInput.validUsername(String(repeating: "a", count: 21), signup: true))
        XCTAssertFalse(AuthenticationInput.validUsername("user@remote"))
        XCTAssertTrue(AuthenticationInput.validUsername("user_1", signup: true))
    }
    func testBackupAndTotpAreDistinct() {
        XCTAssertTrue(AuthenticationInput.validCode("123456"))
        XCTAssertFalse(AuthenticationInput.validCode("12345"))
        XCTAssertTrue(AuthenticationInput.validCode(String(repeating: "A1", count: 16), backup: true))
        XCTAssertFalse(AuthenticationInput.validCode(String(repeating: "a1", count: 16), backup: true))
        XCTAssertFalse(AuthenticationInput.validCode("123456", backup: true))
    }
    func testServerControlsStepAndInvalidFinishedIsRejected() throws {
        XCTAssertEqual(try SigninNext(.object(["next": .string("captcha")])), .password(captcha: true))
        XCTAssertEqual(try SigninNext(.object(["next": .string("totp")])), .totp)
        XCTAssertEqual(try SigninNext(.object(["next": .string("passkey")])), .passkey)
        XCTAssertThrowsError(try SigninNext(.object(["finished": .bool(true)])))
        XCTAssertThrowsError(try SigninNext(.object(["next": .string("unknown")])))
    }
    func testMissingEmailAvailableIsNotSuccess() throws {
        XCTAssertThrowsError(try AccountAvailability.email(.object([:])))
        XCTAssertEqual(try AccountAvailability.email(.object(["available": .bool(false), "reason": .string("used")])), .unavailable("邮箱已被使用"))
    }
    func testSigninErrorIDsAreScopedAndHumanReadable() async throws {
        let transport = TestTransport("{\"error\":{\"id\":\"932c904e-9460-45b7-9ce6-7ed33be7eb2c\"}}", status: 403)
        do { _ = try await APIClient(transport: transport).call("signin-flow", mutation: true); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.code, "SIGNIN_PASSWORD") }
        do { _ = try await APIClient(transport: transport).call("i"); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.code, "HTTP_403") }
    }
    func testAuthSMSOutcomeUnknownDoesNotRetry() async {
        let transport = TestTransport(fail: true)
        do { _ = try await APIClient(transport: transport).call("request-reset-password-phone", mutation: true); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .uncertain) }
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
}
