import XCTest
@testable import PUBOCore

final class ChatContentPolicyTests: XCTestCase {
    func testPreservesUnicodeNewlinesAndEmojiTokens() {
        let text = "你好👋 **粗体**\n:party: @alice :unknown:"
        XCTAssertEqual(ChatContentPolicy.emojiParts(text).joined(), text)
        XCTAssertEqual(ChatContentPolicy.emojiParts(text).filter { $0 == ":party:" }.count, 1)
        XCTAssertEqual(ChatContentPolicy.emojiParts("").count, 0)
    }
    func testLinkOrderFragmentDeduplicationAndBound() {
        let text = "https://example.org/z#one https://example.org/z#two [标题](https://example.com/a) https://example.net https://example.edu"
        XCTAssertEqual(ChatContentPolicy.previewLinks(text).map(\.absoluteString), ["https://example.org/z#one", "https://example.com/a", "https://example.net"])
        XCTAssertTrue(ChatContentPolicy.previewLinks(text, limit: 0).isEmpty)
    }
    func testCodeSilentAndUnsafeURLsDoNotTriggerPreview() {
        let text = "`https://example.com/code` ```\nhttps://example.com/block\n``` ?[silent](https://example.com/silent) https://user:password@example.com https://127.0.0.1/a https://192.168.1.1 https://172.20.0.1 https://example.com/ok。"
        XCTAssertEqual(ChatContentPolicy.previewLinks(text).map(\.absoluteString), ["https://example.com/ok"])
        for value in ["javascript:alert(1)", "file:///tmp/a", "https://localhost/a", "https://[::1]/a", "https://x.local/a", "https://169.254.169.254/latest"] {
            XCTAssertNil(ChatContentPolicy.previewURL(value), value)
        }
    }
}
