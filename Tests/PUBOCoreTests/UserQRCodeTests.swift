import XCTest
@testable import PUBOCore

final class UserQRCodeTests: XCTestCase {
    func testExistingH5UserCode() {
        XCTAssertEqual(UserQRCode.userID(from: "https://bolubo.com/users/abc123"), "abc123")
        XCTAssertEqual(UserQRCode.userID(from: "https://bolubo.com:443/users/abc_123-xyz"), "abc_123-xyz")
    }
    func testRejectsNonUserAndUntrustedCodes() {
        for value in ["https://evil.com/users/abc", "https://bolubo.com.evil.com/users/abc", "http://bolubo.com/users/abc", "https://bolubo.com@evil.com/users/abc", "https://evil@bolubo.com/users/abc", "https://bolubo.com:444/users/abc", "https://bolubo.com/users/", "https://bolubo.com/users/abc/", "https://bolubo.com/users/../login", "https://bolubo.com/users/%61bc", "https://bolubo.com/users/abc?token=x", "https://bolubo.com/users/abc#x", "https://bolubo.com/login", "https://bolubo.com/@abc", "pubonative://login", " abc ", "https://bolubo.com/users/名字"] {
            XCTAssertNil(UserQRCode.userID(from: value), value)
        }
    }
    func testGeneratesValidH5UserCodeURLAndRoundTrips() {
        for id in ["abc123", "abc_123-xyz", "syntheticself", "syntheticuser0001"] {
            let url = UserQRCode.url(forUserID: id)
            XCTAssertEqual(url?.absoluteString, "https://bolubo.com/users/\(id)")
            XCTAssertEqual(url.flatMap { UserQRCode.userID(from: $0.absoluteString) }, id)
        }
    }
    func testRejectsInvalidUserIDsWhenGeneratingURL() {
        for bad in ["", " ", "abc/def", "../login", "abc?x=1", "abc#x", "名字", String(repeating: "a", count: 129)] {
            XCTAssertNil(UserQRCode.url(forUserID: bad), bad)
        }
    }
    func testFormatsH5DisplayHandle() {
        XCTAssertEqual(UserQRCode.displayHandle(username: "fixture"), "@fixture@bolubo.com")
        XCTAssertEqual(UserQRCode.displayHandle(username: "@fixture", host: ""), "@fixture@bolubo.com")
        XCTAssertEqual(UserQRCode.displayHandle(username: "alice", host: "example.social"), "@alice@example.social")
        XCTAssertNil(UserQRCode.displayHandle(username: "   "))
        XCTAssertNil(UserQRCode.displayHandle(username: nil))
    }
}
