import XCTest
@testable import PUBOCore

final class NativeLinksTests: XCTestCase {
    func testRoutesRejectOtherOriginsAndCredentials() {
        XCTAssertEqual(NativeLink(URL(string: "https://bolubo.com/notes/abc123")!), .note("abc123"))
        XCTAssertEqual(NativeLink(URL(string: "https://bolubo.com/@friend@remote.example")!), .handle("friend", "remote.example"))
        for value in ["https://bolubo.com.evil.example/notes/abc", "https://bad@bolubo.com/notes/abc", "http://bolubo.com/notes/abc", "https://bolubo.com:444/notes/abc", "https://bolubo.com/notes/a/b"] { XCTAssertNil(NativeLink(URL(string: value)!)) }
        XCTAssertNil(NativeLink.publicURL("javascript:alert(1)")); XCTAssertNil(NativeLink.publicURL("file:///tmp/secret"))
    }
    func testLinkificationPreservesCodeAndExistingLinks() {
        XCTAssertEqual(NativeLink.linkedText("`@friend #tag` [@x](https://example.com) https://example.com/@u"), "`@friend #tag` [@x](https://example.com) <https://example.com/@u>")
        let text = NativeLink.linkedText("@friend #中文话题 user@example.com")
        XCTAssertTrue(text.contains("[@friend](https://bolubo.com/@friend)")); XCTAssertTrue(text.contains("[#中文话题](https://bolubo.com/tags/")); XCTAssertTrue(text.hasSuffix("user@example.com"))
    }
}
