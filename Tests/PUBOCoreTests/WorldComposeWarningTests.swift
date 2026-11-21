import XCTest
@testable import PUBOCore

final class WorldComposeWarningTests: XCTestCase {
    private func needs(_ text: String, enabled: Bool = true, reply: Bool = false,
                       quote: Bool = false, channel: Bool = false) -> Bool {
        WorldComposeWarning.needsAnnotation(enabled: enabled, text: text,
            isReply: reply, isQuote: quote, isChannel: channel)
    }

    func testEnabledNewWorldPostNeedsNonblankAnnotation() {
        XCTAssertTrue(needs(""))
        XCTAssertTrue(needs("  \t\r\n"))
        XCTAssertTrue(needs("\u{00A0}\u{1680}\u{2009}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"))
        XCTAssertFalse(needs("  内容提示  "))
        XCTAssertFalse(needs("🛰️"))
    }

    func testEcmaTrimDoesNotTreatAdjacentCodePointsAsBlank() {
        for value in ["\u{0008}", "\u{000E}", "\u{0085}", "\u{180E}", "\u{1FFF}", "\u{200B}", "\u{FEFE}"] {
            XCTAssertFalse(needs(" \(value)\u{FEFF}"))
        }
    }

    func testWarningOffAndExistingContextualComposersAreUnaffected() {
        XCTAssertFalse(needs("", enabled: false))
        XCTAssertFalse(needs("", reply: true))
        XCTAssertFalse(needs(" \u{FEFF}", quote: true))
        XCTAssertFalse(needs("\t", channel: true))
        XCTAssertFalse(needs("", reply: true, quote: true, channel: true))
    }

    func testAnnotationPresenceDoesNotEnforceOrChangeExistingLengthRule() {
        let overLimit = String(repeating: "字", count: 101)
        XCTAssertFalse(needs(overLimit))
        XCTAssertNotNil(SendFeedback.limitError(overLimit, limit: 100, label: "内容提示"))
        XCTAssertNil(SendFeedback.limitError(String(repeating: "字", count: 100), limit: 100, label: "内容提示"))
    }
}
