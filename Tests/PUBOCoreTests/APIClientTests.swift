import XCTest
@testable import PUBOCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor TestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let status: Int
    let body: String
    let fail: Bool
    init(_ body: String = "{}", status: Int = 200, fail: Bool = false) { self.body = body; self.status = status; self.fail = fail }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if fail { throw URLError(.timedOut) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class APIClientTests: XCTestCase {
    func testPrivateAttachmentUsesHeaderNotQuery() async throws {
        let transport = TestTransport("file")
        _ = try await APIClient(transport: transport).privateAttachment(id: "testid", token: "synthetic-token")
        let request = await transport.requests[0]
        XCTAssertEqual(request.url?.path, "/api/chat/attachments/testid/original")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
    }
    func testCallerCannotInjectTokenIntoBody() async throws {
        let transport = TestTransport()
        _ = try await APIClient(transport: transport).call("meta", body: ["i": .string("injected")])
        let request = await transport.requests[0]
        let data = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
        XCTAssertTrue(data["i"].isNull)
    }
    func testLostMutationResponseIsNotRetried() async throws {
        let transport = TestTransport(fail: true)
        do { _ = try await APIClient(transport: transport).call("notes/create", mutation: true); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.code, "OUTCOME_UNKNOWN") }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }
    func testReplyRequiredPreservesBusinessReason() async throws {
        let transport = TestTransport("{\"error\":{\"code\":\"CHAT_REPLY_REQUIRED\"}}", status: 400)
        do { _ = try await APIClient(transport: transport).call("chat/messages/create-to-user", mutation: true); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.message, "对方未回复之前只能发送一条消息，等对方回复以后才可以继续留言") }
    }
    func testServerFailureOnMutationIsUncertain() async throws {
        do { _ = try await APIClient(transport: TestTransport(status: 502)).call("notes/create", mutation: true); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .uncertain) }
    }
    func testReconciliationRejectsDifferentAttachments() throws {
        let item = PendingChat(recipientID: "peer", text: "hello", attachmentIDs: ["a", "b"])
        let message = Record(.object(["id": .string("note"), "clientMessageId": .string(item.id), "fromUserId": .string("self"), "text": .string("hello"), "attachments": .array([.object(["id": .string("b")]), .object(["id": .string("a")])])]))
        XCTAssertFalse(item.matches(message, authorID: "self"))
    }
    func testRestartDoesNotRestoreSendingAsReady() {
        var item = PendingChat(recipientID: "peer", text: "hello")
        item.state = .sending
        XCTAssertEqual(OutboxRecovery.restore([item]).first?.state, .uncertain)
        XCTAssertTrue(OutboxRecovery.restore([item], now: Date().addingTimeInterval(86_401)).isEmpty)
    }
    func testRealtimeMergeDeduplicatesAndUpdates() {
        let a = Record(.object(["id": .string("a"), "text": .string("old")]))
        let updated = Record(.object(["id": .string("a"), "text": .string("new")]))
        XCTAssertEqual(Records.merge([a], [updated, updated]), [updated])
    }
    func testAscendingChatWindowKeepsNewestMessages() {
        let items = ["a", "b", "c"].map { Record(.object(["id": .string($0)])) }
        XCTAssertEqual(Records.merge([], items, newestFirst: false, limit: 2).map(\.id), ["b", "c"])
    }
    func testReconciliationRejectsDifferentRecipientAndReply() {
        let item = PendingChat(recipientID: "peer", text: "test", replyToID: "quoted")
        let fields: [String: JSONValue] = ["id": .string("msg"), "clientMessageId": .string(item.id), "fromUserId": .string("self"), "toUserId": .string("peer"), "text": .string("test"), "replyToId": .string("quoted"), "attachments": .array([])]
        XCTAssertTrue(item.matches(Record(.object(fields)), authorID: "self"))
        var wrong = fields; wrong["toUserId"] = .string("another")
        XCTAssertFalse(item.matches(Record(.object(wrong)), authorID: "self"))
        wrong = fields; wrong["replyToId"] = .null
        XCTAssertFalse(item.matches(Record(.object(wrong)), authorID: "self"))
    }
    func testKnownSMSFailureIsHumanReadable() async throws {
        let transport = TestTransport("{\"message\":\"INVALID_SMS_CODE\"}", status: 400)
        do { _ = try await APIClient(transport: transport).call("signup", mutation: true); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.code, "INVALID_SMS_CODE") }
    }
    func testRateLimitDoesNotRetry() async throws {
        let transport = TestTransport("{}", status: 429)
        do { _ = try await APIClient(transport: transport).call("meta"); XCTFail() } catch { XCTAssertEqual((error as? APIError)?.code, "HTTP_429") }
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testInvalidSuccessfulMutationResponseIsUncertain() async throws {
        do { _ = try await APIClient(transport: TestTransport("not-json")).call("notes/create", mutation: true); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .uncertain) }
    }
    func testSignedMediaCannotRedirect() async throws {
        let transport = TestTransport("", status: 302)
        do { _ = try await APIClient(transport: transport).privateAttachment(id: "fixture", token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.code, "ATTACHMENT_UNAVAILABLE") }
    }
    func testMalformedPrivateIDIsRejectedBeforeRequest() async throws {
        let transport = TestTransport()
        do { _ = try await APIClient(transport: transport).privateAttachment(id: "../drive", token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    func testPostReceiptRequiresAuthorVisibilityAndOrderedFiles() {
        let body: [String: JSONValue] = ["text": .string("fixture"), "visibility": .string("followers"), "fileIds": .strings(["a", "b"])]
        var note: [String: JSONValue] = ["id": .string("note"), "user": .object(["id": .string("self")]), "text": .string("fixture"), "visibility": .string("followers"), "files": .array([.object(["id": .string("a")]), .object(["id": .string("b")])])]
        XCTAssertTrue(NoteReceipt.matches(.object(["createdNote": .object(note)]), authorID: "self", request: body))
        XCTAssertFalse(NoteReceipt.matches(.object(["createdNote": .object(note)]), authorID: "other", request: body))
        note["visibility"] = .string("public")
        XCTAssertFalse(NoteReceipt.matches(.object(["createdNote": .object(note)]), authorID: "self", request: body))
        note["visibility"] = .string("followers"); note["files"] = .array([.object(["id": .string("b")]), .object(["id": .string("a")])])
        XCTAssertFalse(NoteReceipt.matches(.object(["createdNote": .object(note)]), authorID: "self", request: body))
    }
}
