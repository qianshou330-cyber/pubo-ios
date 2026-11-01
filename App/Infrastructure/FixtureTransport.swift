import Foundation
import PUBOCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic deterministic transport. Only AppSession's DEBUG launch argument enables it.
/// No production request is made from UI tests, including image and WebSocket traffic.
actor FixtureTransport: HTTPTransport {
    static let me: JSONValue = .object(["id": .string("syntheticself"), "username": .string("fixture"), "name": .string("测试用户"), "host": .null, "chatScope": .string("mutual"), "roles": .array([]), "followingCount": .number(1), "followersCount": .number(1), "policies": .object(["ltlAvailable": .bool(true), "gtlAvailable": .bool(true)])])
    static let peer: JSONValue = .object(["id": .string("syntheticpeer"), "username": .string("friend"), "name": .string("测试朋友"), "host": .null])
    private var sent: [JSONValue] = []
    private var counter = 0
    private var timelineReads = 0
    private var favorites = Set<String>()
    private var profile = FixtureTransport.me
    private let driveFile: JSONValue = .object(["id": .string("fixturefile"), "name": .string("测试图片.png"), "type": .string("image/png"), "size": .number(128), "isSensitive": .bool(false)])
    init() {
        if ProcessInfo.processInfo.arguments.contains("--social-preview") {
            posts.insert(.object(["id": .string("fixturepoll003"), "user": Self.peer, "text": .string("测试投票"), "cw": .null, "files": .array([]), "reactions": .object([:]), "poll": .object(["multiple": .bool(false), "expiresAt": .null, "choices": .array([.object(["text": .string("选项 A"), "votes": .number(2), "isVoted": .bool(false)]), .object(["text": .string("选项 B"), "votes": .number(0), "isVoted": .bool(false)])])])]), at: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--chat-preview") {
            sent = [
                .object(["id": .string("chatpreview001"), "fromUserId": .string("syntheticpeer"), "toUserId": .string("syntheticself"), "text": .string("你好，欢迎来到 PUBO。"), "createdAt": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))), "attachments": .array([])]),
                .object(["id": .string("chatpreview002"), "fromUserId": .string("syntheticself"), "toUserId": .string("syntheticpeer"), "text": .string("收到，我们在这里聊天。"), "createdAt": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))), "attachments": .array([]), "readState": .string("read")])
            ]
        }
    }
    private var posts: [JSONValue] = [
        .object(["id": .string("fixturepost002"), "user": FixtureTransport.me, "text": .string("欢迎来到 PUBO。原生界面测试 :test:"), "cw": .null, "files": .array([]), "reactions": .object(["❤️": .number(1)])]),
        .object(["id": .string("fixturepost001"), "user": FixtureTransport.peer, "text": .string("这段文字需要展开内容警告后查看"), "cw": .string("内容提示"), "files": .array([]), "reactions": .object([:])])
    ]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path.replacingOccurrences(of: "/api/", with: "")
        let body = (try? JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())) ?? .null
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--slow-startup"), path == "i" { try await Task.sleep(for: .seconds(5)) }
        if args.contains("--skeleton-loading"), path.contains("timeline") || path == "announcements" || path == "music-charts/kpop-summary" { try await Task.sleep(for: .seconds(7)) }
        if args.contains("--skeleton-failure"), path.contains("timeline") { try await Task.sleep(for: .seconds(4)); throw URLError(.timedOut) }
        if args.contains("--network-error"), path.contains("timeline") { throw URLError(.timedOut) }
        if args.contains("--slow"), path == "emojis" { try await Task.sleep(for: .seconds(20)) }
        if args.contains("--slow-home-panels"), path == "announcements" || path == "music-charts/kpop-summary" { try await Task.sleep(for: .seconds(20)) }
        if args.contains("--failed-home-panels"), path == "announcements" || path == "music-charts/kpop-summary" { throw URLError(.timedOut) }
        var response: JSONValue = .object([:])
        var status = 200
        if args.contains("--permission-denied"), ["i/favorites", "notes/favorites/create", "notes/polls/vote"].contains(path) {
            return (try JSONEncoder().encode(JSONValue.object(["error": .object(["code": .string("PERMISSION_DENIED")])])), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }
        switch path {
        case "meta": response = .object(["name": .string("PUBO"), "disableRegistration": .bool(false), "emailRequiredForSignup": .bool(false)])
        case "emojis": response = .object(["emojis": .array([])])
        case "i": response = profile
        case "i/update": var values = profile.object; for (key, value) in body.object where key != "i" { values[key] = value }; profile = .object(values); response = profile
        case "signin-flow": response = .object(["finished": .bool(true), "i": .string("synthetic-session"), "id": .string("syntheticself")])
        case "signup": response = .object(["token": .string("synthetic-session"), "id": .string("syntheticself")])
        case "signup/request-phone-code": response = .null
        case "users/show": response = body["userId"].string == "syntheticself" ? Self.me : Self.peer
        case "users/search": response = .array([Self.peer])
        case "notes/search": response = .array(posts.filter { ($0["text"].string ?? "").localizedCaseInsensitiveContains(body["query"].string ?? "") })
        case "hashtags/search": response = .strings(["PUBO", "A2OLITE"])
        case "notes/search-by-tag": response = .array(posts)
        case "drive/folders": response = body["folderId"].isNull ? .array([.object(["id": .string("fixturefolder"), "name": .string("测试文件夹")])]) : .array([])
        case "drive/files": response = .array([driveFile])
        case "notes/state": response = .object(["isFavorited": .bool(favorites.contains(body["noteId"].string ?? ""))])
        case "notes/favorites/create": favorites.insert(body["noteId"].string ?? ""); response = .null
        case "notes/favorites/delete": favorites.remove(body["noteId"].string ?? ""); response = .null
        case "i/favorites": response = .array(posts.filter { favorites.contains($0["id"].string ?? "") }.map { .object(["id": .string("saved-" + ($0["id"].string ?? "")), "note": $0]) })
        case "notes/delete": posts.removeAll { $0["id"] == body["noteId"] }; response = .null
        case "notes/polls/vote":
            if let index = posts.firstIndex(where: { $0["id"] == body["noteId"] }) {
                var post = posts[index].object; var poll = post["poll"]!.object; var choices = poll["choices"]!.array
                let choice = body["choice"].int
                if choices.indices.contains(choice) { var value = choices[choice].object; value["votes"] = .number(Double(choices[choice]["votes"].int + 1)); value["isVoted"] = .bool(true); choices[choice] = .object(value) }
                poll["choices"] = .array(choices); post["poll"] = .object(poll); posts[index] = .object(post)
            }; response = .null
        case "users/following": response = .array([.object(["id": .string("relation1"), "followee": Self.peer])])
        case "users/followers": response = .array([.object(["id": .string("relation1"), "follower": Self.peer])])
        case "notes/home-timeline", "notes/local-timeline", "notes/hybrid-timeline", "notes/global-timeline", "users/notes":
            if args.contains("--refreshable-feed"), path != "users/notes" {
                timelineReads += 1
                let sample: JSONValue = .object(["id": .string(String(format: "refresh%08d", timelineReads)), "user": Self.me,
                    "text": .string("刷新样例 \(timelineReads)"), "cw": .null, "files": .array([]), "reactions": .object([:])])
                response = .array([sample] + posts)
            } else { response = .array(posts) }
        case "announcements": response = .array([.object(["id": .string("fixtureannouncement"), "display": .string("marquee"), "forYou": .bool(false), "title": .string("欢迎加入 PUBO"), "text": .string("这是隔离测试公告，不会发布到生产。")])])
        case "music-charts/kpop-summary", "music-charts/kpop-chart":
            let key = body["chartKey"].string ?? "melon-top100"
            let chart = JSONValue.object(["chartKey": .string(key), "provider": .string(key == "genie-realtime" ? "genie" : "melon"), "label": .string(key == "genie-realtime" ? "Genie 实时榜" : "Melon TOP100"), "status": .string("available"), "rankBasis": .string("official_rank"), "coverage": .string("complete"), "lastSuccessAt": .string("2026-11-01T15:00:00Z")])
            let song = JSONValue.object(["songId": .string("fixturesong"), "title": .string("NEON"), "artists": .array([.object(["name": .string("A2O LITE")])]), "rank": .number(1), "groupIds": .strings(["a2o-lite"]), "sourceMovement": .object(["type": .string("same")])])
            response = .object(["selected": chart, "chart": chart, "charts": .array([chart, .object(["chartKey": .string("genie-realtime"), "label": .string("Genie 实时榜")])]), "entries": .array([song]), "total": .number(1), "hasMore": .bool(false)])
        case "music-charts/kpop-history": response = .object(["basis": .string("observation"), "points": .array([.object(["observedAt": .string("2026-11-01T15:00:00Z"), "result": .string("ranked"), "rank": .number(1)])])])
        case "notes/show": response = posts.first { $0["id"] == body["noteId"] } ?? posts[0]
        case "notes/replies": response = .array([])
        case "notes/create":
            counter += 1
            let poll: JSONValue = body["poll"].isNull ? .null : .object(["choices": .array(body["poll"]["choices"].array.map { .object(["text": $0, "votes": .number(0), "isVoted": .bool(false)]) }), "multiple": body["poll"]["multiple"], "expiresAt": body["poll"]["expiresAt"].isNull ? .null : .string(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(body["poll"]["expiresAt"].int) / 1000)))])
            let note = JSONValue.object(["id": .string("newpost\(counter)"), "user": Self.me, "text": body["text"], "cw": body["cw"], "visibility": body["visibility"], "replyId": body["replyId"], "renoteId": body["renoteId"], "files": .array(body["fileIds"].array.map { .object(["id": $0, "name": .string("测试图片.png")]) }), "reactions": .object([:]), "poll": poll])
            posts.insert(note, at: 0); response = .object(["createdNote": note])
            if args.contains("--lost-post-response") { throw URLError(.networkConnectionLost) }
        case "i/notifications": response = .array([.object(["id": .string("notice1"), "type": .string("follow"), "user": Self.peer, "isRead": .bool(false)])])
        case "chat/conversations": response = .array([.object(["user": Self.peer, "lastMessage": .object(["id": .string("seedmessage"), "text": .string("点击开始聊天")]), "unreadCount": .number(0), "isMuted": .bool(false), "pinnedAt": .null])])
        case "chat/messages/user-timeline": response = .array(sent)
        case "chat/messages/show": response = sent.first { $0["id"] == body["messageId"] } ?? .null
        case "chat/messages/state":
            let ids = body["messageIds"].array.compactMap(\.string)
            response = .object(["messages": .array(sent.filter { ids.contains($0["id"].string ?? "") }), "missingIds": .strings(ids.filter { id in !sent.contains { $0["id"].string == id } })])
        case "chat/messages/update":
            if let index = sent.firstIndex(where: { $0["id"] == body["messageId"] }) {
                if args.contains("--edit-conflict") && sent[index]["revision"].int == 0 {
                    var value = sent[index].object; value["revision"] = .number(1); value["text"] = .string("另一台设备已编辑"); sent[index] = .object(value)
                }
                if sent[index]["revision"].int != body["expectedRevision"].int { status = 400; response = .object(["error": .object(["code": .string("MESSAGE_CONFLICT")])]) }
                else {
                    var value = sent[index].object; value["text"] = body["text"]; value["revision"] = .number(Double(sent[index]["revision"].int + 1)); value["editedAt"] = .string(ISO8601DateFormatter().string(from: Date())); sent[index] = .object(value); response = sent[index]
                    if args.contains("--lost-edit-response") { throw URLError(.networkConnectionLost) }
                }
            }
        case "chat/messages/delete":
            if let index = sent.firstIndex(where: { $0["id"] == body["messageId"] }) { var value = sent[index].object; value["text"] = .null; value["attachments"] = .array([]); value["reactions"] = .array([]); value["recalledAt"] = .string(ISO8601DateFormatter().string(from: Date())); value["revision"] = .number(Double(sent[index]["revision"].int + 1)); sent[index] = .object(value) }; response = .null
        case "chat/messages/react", "chat/messages/unreact":
            if let index = sent.firstIndex(where: { $0["id"] == body["messageId"] }) {
                var value = sent[index].object; var reactions = sent[index]["reactions"].array
                let reaction = SocialContent.chatReactionKey(body["reaction"].string ?? "")
                if path.hasSuffix("/react") { reactions.append(.object(["user": Self.me, "reaction": .string(reaction)])) }
                else { reactions.removeAll { $0["user"]["id"] == Self.me["id"] && SocialContent.chatReactionKey($0["reaction"].string ?? "") == reaction } }
                value["reactions"] = .array(reactions); sent[index] = .object(value)
            }; response = .null
        case "chat/messages/create-to-user":
            if let previous = sent.first(where: { $0["clientMessageId"] == body["clientMessageId"] }) { response = previous }
            else if !sent.isEmpty || args.contains("--reply-required") { status = 400; response = .object(["error": .object(["code": .string("CHAT_REPLY_REQUIRED")])]) }
            else {
                counter += 1
                response = .object(["id": .string("chat\(counter)"), "fromUserId": .string("syntheticself"), "toUserId": .string("syntheticpeer"), "text": body["text"], "attachments": .array([]), "clientMessageId": body["clientMessageId"], "readState": .string("unread")])
                sent.append(response)
                if args.contains("--lost-chat-response") { throw URLError(.networkConnectionLost) }
            }
        case "chat/attachments/create", "chat/attachments/import-drive": status = 400; response = .object(["error": .object(["code": .string("CHAT_FIRST_MESSAGE_TEXT_ONLY")])])
        default: response = .null
        }
        let data = try JSONEncoder().encode(response)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}
