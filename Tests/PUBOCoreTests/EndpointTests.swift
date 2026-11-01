import XCTest
@testable import PUBOCore

final class EndpointTests: XCTestCase {
    func testOnlyOfficialOriginCanReceiveCredentials() throws {
        XCTAssertTrue(Endpoint.isTrusted(try Endpoint.api("chat/messages/create-to-user")))
        for value in ["http://bolubo.com", "https://bolubo.com.evil.test", "https://bolubo.com:8443", "https://user@bolubo.com"] {
            XCTAssertFalse(Endpoint.isTrusted(URL(string: value)!))
        }
    }
    func testEndpointCannotEscapeOrigin() {
        for path in ["../i", "/i", "https://other.test/i", "i?token=x", "i#x"] {
            XCTAssertThrowsError(try Endpoint.api(path))
        }
    }
}
