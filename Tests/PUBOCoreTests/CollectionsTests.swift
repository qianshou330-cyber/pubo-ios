import XCTest
@testable import PUBOCore

final class CollectionsTests: XCTestCase {
    func testLegacyUpdatesPreserveUneditedDescriptionAndSensitivity() {
        let latest: JSONValue = .object(["description": .string("Changed on another device"), "isSensitive": .bool(true)])
        XCTAssertEqual(CollectionFields.update(["name": .string("New title")], kind: .clip, latest: latest)["description"], latest["description"])
        XCTAssertEqual(CollectionFields.update(["title": .string("New title")], kind: .gallery, latest: latest)["isSensitive"], .bool(true))
        XCTAssertEqual(CollectionFields.update(["description": .string("")], kind: .clip, latest: latest)["description"], .null)
        XCTAssertEqual(CollectionFields.update(["isSensitive": .bool(false)], kind: .gallery, latest: latest)["isSensitive"], .bool(false))
        XCTAssertNil(CollectionFields.update(["name": .string("New")], kind: .list, latest: latest)["description"])
    }
    func testAntennaKeywordLinesPreserveAndOrGroups() {
        let result = CollectionFields.keywords("  hello world\n\nPUBO  新闻\r\n  ")
        XCTAssertEqual(result, .array([.strings(["hello", "world"]), .strings(["PUBO", "新闻"])]))
        XCTAssertEqual(CollectionFields.keywords(CollectionFields.keywordText(result)), result)
        XCTAssertEqual(CollectionFields.keywords(" \n"), .array([]))
    }
    func testOnlyChangedFieldsAreSubmittedIncludingExplicitRemoval() {
        let original: [String: JSONValue] = ["name": .string("公开频道"), "bannerId": .string("oldfile"), "unknownServerSetting": .bool(true), "isArchived": .bool(false)]
        let edit: [String: JSONValue] = ["name": .string("公开频道"), "bannerId": .null, "isArchived": .bool(true)]
        XCTAssertEqual(CollectionFields.changes(edit, from: original), ["bannerId": .null, "isArchived": .bool(true)])
        XCTAssertEqual(original["unknownServerSetting"], .bool(true))
    }
    func testNoteReceiptRejectsWrongChannelWithoutDiscardingDraft() {
        let request: [String: JSONValue] = ["text": .string("channel test"), "visibility": .string("public"), "channelId": .string("correct")]
        var note: [String: JSONValue] = ["id": .string("post"), "user": .object(["id": .string("owner")]), "text": .string("channel test"), "visibility": .string("public"), "channelId": .string("wrong")]
        XCTAssertFalse(NoteReceipt.matches(.object(["createdNote": .object(note)]), authorID: "owner", request: request))
        note["channelId"] = .string("correct")
        XCTAssertTrue(NoteReceipt.matches(.object(["createdNote": .object(note)]), authorID: "owner", request: request))
    }
}
