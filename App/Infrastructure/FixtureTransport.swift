import Foundation
import PUBOCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic deterministic transport. Only AppSession's DEBUG launch argument enables it.
/// No production request is made from UI tests, including image and WebSocket traffic.
actor FixtureTransport: HTTPTransport {
    static let me: JSONValue = .object(["id": .string("syntheticself"), "username": .string("fixture"), "name": .string("测试用户"), "host": .null, "chatScope": .string("mutual"), "roles": .array([]), "followingCount": .number(1), "followersCount": .number(1)])
    static let peer: JSONValue = .object(["id": .string("syntheticpeer"), "username": .string("friend"), "name": .string("测试朋友"), "host": .null])
    private var sent: [JSONValue] = []
    private var counter = 0
    private var posts: [JSONValue] = [
        .object(["id": .string("fixturepost002"), "user": FixtureTransport.me, "text": .string("欢迎来到 PUBO。原生界面测试 :test:"), "cw": .null, "files": .array([]), "reactions": .object(["❤️": .number(1)])]),
        .object(["id": .string("fixturepost001"), "user": FixtureTransport.peer, "text": .string("这段文字需要展开内容警告后查看"), "cw": .string("内容提示"), "files": .array([]), "reactions": .object([:])])
    ]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path.replacingOccurrences(of: "/api/", with: "")
        let body = (try? JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())) ?? .null
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--network-error"), path.contains("timeline") { throw URLError(.timedOut) }
        if args.contains("--slow"), path == "emojis" { try await Task.sleep(for: .seconds(20)) }
        var response: JSONValue = .object([:])
        var status = 200
        switch path {
        case "meta": response = .object(["name": .string("PUBO"), "disableRegistration": .bool(false), "emailRequiredForSignup": .bool(false)])
        case "emojis": response = .object(["emojis": .array([])])
        case "i": response = Self.me
        case "signin-flow": response = .object(["finished": .bool(true), "i": .string("synthetic-session"), "id": .string("syntheticself")])
        case "signup": response = .object(["token": .string("synthetic-session"), "id": .string("syntheticself")])
        case "signup/request-phone-code": response = .null
        case "users/show": response = body["userId"].string == "syntheticself" ? Self.me : Self.peer
        case "users/search": response = .array([Self.peer])
        case "users/following": response = .array([.object(["id": .string("relation1"), "followee": Self.peer])])
        case "users/followers": response = .array([.object(["id": .string("relation1"), "follower": Self.peer])])
        case "notes/home-timeline", "notes/local-timeline", "notes/global-timeline", "users/notes": response = .array(posts)
        case "notes/show": response = posts.first { $0["id"] == body["noteId"] } ?? posts[0]
        case "notes/replies": response = .array([])
        case "notes/create":
            counter += 1
            let note = JSONValue.object(["id": .string("newpost\(counter)"), "user": Self.me, "text": body["text"], "cw": body["cw"], "visibility": body["visibility"], "replyId": body["replyId"], "renoteId": body["renoteId"], "files": .array([]), "reactions": .object([:])])
            posts.insert(note, at: 0); response = .object(["createdNote": note])
            if args.contains("--lost-post-response") { throw URLError(.networkConnectionLost) }
        case "i/notifications": response = .array([.object(["id": .string("notice1"), "type": .string("follow"), "user": Self.peer, "isRead": .bool(false)])])
        case "chat/conversations": response = .array([.object(["user": Self.peer, "lastMessage": .object(["id": .string("seedmessage"), "text": .string("点击开始聊天")]), "unreadCount": .number(0), "isMuted": .bool(false), "pinnedAt": .null])])
        case "chat/messages/user-timeline": response = .array(sent)
        case "chat/messages/create-to-user":
            if let previous = sent.first(where: { $0["clientMessageId"] == body["clientMessageId"] }) { response = previous }
            else if !sent.isEmpty || args.contains("--reply-required") { status = 400; response = .object(["error": .object(["code": .string("CHAT_REPLY_REQUIRED")])]) }
            else {
                counter += 1
                response = .object(["id": .string("chat\(counter)"), "fromUserId": .string("syntheticself"), "toUserId": .string("syntheticpeer"), "text": body["text"], "attachments": .array([]), "clientMessageId": body["clientMessageId"], "readState": .string("unread")])
                sent.append(response)
                if args.contains("--lost-chat-response") { throw URLError(.networkConnectionLost) }
            }
        case "chat/attachments/create": status = 400; response = .object(["error": .object(["code": .string("CHAT_FIRST_MESSAGE_TEXT_ONLY")])])
        default: response = .null
        }
        let data = try JSONEncoder().encode(response)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}
