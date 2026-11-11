import XCTest
@testable import PUBOCore

final class ProfilePresentationTests: XCTestCase {
    func testH5NameAndDescriptionBoundary() {
        XCTAssertNil(ProfilePresentation.validationError(name: String(repeating: "中", count: 30), description: String(repeating: "文", count: 500), birthday: "", fieldCount: 16))
        XCTAssertNotNil(ProfilePresentation.validationError(name: String(repeating: "中", count: 31), description: "", birthday: "", fieldCount: 0))
        XCTAssertNotNil(ProfilePresentation.validationError(name: "", description: String(repeating: "文", count: 501), birthday: "", fieldCount: 0))
        XCTAssertNotNil(ProfilePresentation.validationError(name: "", description: "", birthday: "", fieldCount: 17))
        XCTAssertEqual(ProfilePresentation.length("😀"), 1)
    }
    func testStrictBirthdayWithoutTimezoneConversion() {
        for value in ["", "2000-02-29", "2024-12-31", "2030-01-01"] { XCTAssertTrue(ProfilePresentation.validBirthday(value), value) }
        for value in ["2023-02-29", "2024-02-30", "2024-13-01", "2024-00-01", "2024-1-1", "0000-01-01", "２０２４-01-01", "2024-01-01T00:00:00Z"] { XCTAssertFalse(ProfilePresentation.validBirthday(value), value) }
    }
    func testEmptyProfileTextClearsUsingNull() {
        XCTAssertEqual(ProfilePresentation.optionalText(""), .null)
        XCTAssertEqual(ProfilePresentation.optionalText("Tokyo"), .string("Tokyo"))
    }
    func testIncompleteMetadataRowsMatchH5Filtering() {
        let result = ProfilePresentation.fields([("", "value"), ("name", ""), ("website", "https://example.com"), ("name", "value")])
        XCTAssertEqual(result.array.count, 2)
        XCTAssertEqual(result.array[0]["name"].string, "website")
    }
    func testVerifiedLinkRequiresExactServerListMatch() {
        let links = JSONValue.strings(["https://example.com"])
        XCTAssertTrue(ProfilePresentation.verified("https://example.com", links: links))
        XCTAssertFalse(ProfilePresentation.verified("https://example.com.evil", links: links))
        XCTAssertFalse(ProfilePresentation.verified("", links: .strings([""])))
    }
}
