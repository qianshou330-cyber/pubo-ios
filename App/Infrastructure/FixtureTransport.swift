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
    #if DEBUG
    private var gifReads = 0
    private var stickerUpload: Data?
    #endif
    private var chartReads = 0
    private var favorites = Set<String>()
    private var profile = FixtureTransport.me
    private var oldMessage: JSONValue = .null
    private var driveFile: JSONValue = .object(["id": .string("fixturefile"), "name": .string("测试图片.png"), "type": .string("image/png"), "size": .number(128), "isSensitive": .bool(false)])
    private var announcements: [JSONValue] = [.object(["id": .string("fixtureannouncement"), "display": .string("marquee"), "forYou": .bool(false), "isActive": .bool(true), "title": .string("欢迎加入 PUBO"), "text": .string("这是隔离测试公告，不会发布到生产。"), "updatedAt": .string("2026-11-02T00:00:00Z")])]
    private var drafts: [JSONValue] = []
    private var contacts: [JSONValue] = []
    private var rooms: [JSONValue] = []
    private var roomMessages: [JSONValue] = []
    private var collections: [String: [JSONValue]] = [:]
    private var invitations: [JSONValue] = []
    private var conversationPreference: JSONValue = .object(["pinnedAt": .null, "isMuted": .bool(false)])
    private var mutedUsers: [JSONValue] = []
    private var driveFolders: [JSONValue] = [.object(["id": .string("fixturefolder"), "name": .string("测试文件夹"), "parentId": .null])]
    init() {
        var user = profile.object; var policies = user["policies"]!.object
        policies["scheduledNoteLimit"] = .number(10); policies["avatarDecorationLimit"] = .number(2)
        user["policies"] = .object(policies); user["isAdmin"] = .bool(ProcessInfo.processInfo.arguments.contains("--admin-preview")); profile = .object(user)
        if ProcessInfo.processInfo.arguments.contains("--moderator-preview") { var values = profile.object; values["isModerator"] = .bool(true); profile = .object(values) }
        if ProcessInfo.processInfo.arguments.contains("--empty-announcements") { announcements = [] }
        if ProcessInfo.processInfo.arguments.contains("--home-motion") {
            announcements = [PublicHomeSnapshot.value["announcement"]]
            if ProcessInfo.processInfo.arguments.contains("--multiple-announcements") { announcements.append(.object(["id": .string("fixtureannouncement2"), "display": .string("marquee"), "isActive": .bool(true), "silence": .bool(true), "title": .string("音乐与朋友，让每一天更精彩"), "text": .string("这是第二条公开公告的隔离样例。")])) }
            announcements.append(.object(["id": .string("fixturepast"), "display": .string("normal"), "isActive": .bool(false), "title": .string("历史公告样例"), "text": .string("已结束公告仍可查看。")]))
        }
        posts = posts.map { var value = $0.object; value["visibility"] = .string("public"); return .object(value) }
        if ProcessInfo.processInfo.arguments.contains("--search-unavailable") {
            var value = profile.object; var policies = value["policies"]!.object
            policies["canSearchNotes"] = .bool(false); policies["canSearchUsers"] = .bool(true)
            value["policies"] = .object(policies); profile = .object(value)
        }
        if ProcessInfo.processInfo.arguments.contains("--social-preview") {
            posts.insert(.object(["id": .string("fixturepoll003"), "user": Self.peer, "text": .string("测试投票"), "cw": .null, "files": .array([]), "reactions": .object([:]), "poll": .object(["multiple": .bool(false), "expiresAt": .null, "choices": .array([.object(["text": .string("选项 A"), "votes": .number(2), "isVoted": .bool(false)]), .object(["text": .string("选项 B"), "votes": .number(0), "isVoted": .bool(false)])])])]), at: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--chat-preview") {
            sent = [
                .object(["id": .string("chatpreview001"), "fromUserId": .string("syntheticpeer"), "toUserId": .string("syntheticself"), "text": .string("你好，欢迎来到 PUBO。"), "createdAt": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))), "attachments": .array([])]),
                .object(["id": .string("chatpreview002"), "fromUserId": .string("syntheticself"), "toUserId": .string("syntheticpeer"), "text": .string("收到，我们在这里聊天。"), "createdAt": .string(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))), "attachments": .array([]), "readState": .string("read")])
            ]
        }
        if ProcessInfo.processInfo.arguments.contains("--parity-preview") {
            oldMessage = .object(["id": .string("chatold000"), "fromUserId": .string("syntheticpeer"), "toUserId": .string("syntheticself"), "text": .string("历史原消息已更新"), "revision": .number(2), "attachments": .array([]), "readState": .string("unread")])
            sent = [.object(["id": .string("chatquote003"), "fromUserId": .string("syntheticself"), "toUserId": .string("syntheticpeer"), "text": .string("引用历史消息"), "attachments": .array([]), "replyToId": .string("chatold000"), "replyTo": .object(["id": .string("chatold000"), "text": .string("旧正文不应保留"), "revision": .number(1)])])]
            var values = profile.object; values["hasUnreadNotification"] = .bool(true); profile = .object(values)
        }
        if ProcessInfo.processInfo.arguments.contains("--social-align") {
            let now = "2026-11-03T10:00:00Z"
            let origin: JSONValue = .object(["id": .string("socialorigin"), "user": Self.peer, "text": .string("周末一起听歌吧，记得带上耳机。"), "files": .array([]), "createdAt": .string(now), "visibility": .string("public")])
            posts = [
                .object(["id": .string("socialquote"), "user": Self.me, "text": .string("好呀，我也准备好了歌单。"), "renoteId": origin["id"], "renote": origin, "createdAt": .string(now), "visibility": .string("public")]),
                .object(["id": .string("socialreply"), "user": Self.peer, "text": .string("下午三点见。"), "replyId": origin["id"], "reply": origin, "createdAt": .string(now), "visibility": .string("public")]),
                .object(["id": .string("socialmissing"), "user": Self.me, "text": .string("这条引用的原帖已不可用。"), "renoteId": .string("removed"), "renote": .null, "createdAt": .string(now)]), origin]
            rooms = [.object(["id": .string("socialroom"), "name": .string("PUBO 音乐交流"), "ownerId": Self.peer["id"], "description": .string("一起分享音乐和日常。"), "isMuted": .bool(false)])]
            roomMessages = [
                .object(["id": .string("room0001"), "toRoomId": .string("socialroom"), "fromUserId": Self.peer["id"], "fromUser": Self.peer, "text": .string("欢迎来到音乐交流群。"), "createdAt": .string(now), "reactions": .array([.object(["user": Self.me, "reaction": .string("❤")])])]),
                .object(["id": .string("room0002"), "toRoomId": .string("socialroom"), "fromUserId": Self.me["id"], "fromUser": Self.me, "text": .string("大家好，很高兴认识你们。"), "createdAt": .string(now), "reactions": .array([])])]
            sent = [
                .object(["id": .string("private0001"), "fromUserId": Self.peer["id"], "toUserId": Self.me["id"], "text": .string("你好，欢迎来到 PUBO。"), "createdAt": .string(now), "attachments": .array([]), "reactions": .array([.object(["user": Self.me, "reaction": .string("❤")])])]),
                .object(["id": .string("private0002"), "fromUserId": Self.me["id"], "toUserId": Self.peer["id"], "text": .string("收到，我们在这里聊天。"), "createdAt": .string(now), "attachments": .array([]), "readState": .string("read")])]
            var policy = profile["policies"].object; policy["chatAvailability"] = .string("available"); var updated = profile.object; updated["policies"] = .object(policy); profile = .object(updated)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--timeline-align") { posts = TimelineTestFixtures.posts; announcements = TimelineTestFixtures.snapshot["announcements"].array }
        #endif
    }
    private var posts: [JSONValue] = [
        .object(["id": .string("fixturepost002"), "user": FixtureTransport.me, "text": .string("欢迎来到 PUBO。原生界面测试 :test:"), "cw": .null, "files": .array([]), "reactions": .object(["❤️": .number(1)])]),
        .object(["id": .string("fixturepost001"), "user": FixtureTransport.peer, "text": .string("这段文字需要展开内容警告后查看"), "cw": .string("内容提示"), "files": .array([]), "reactions": .object([:])])
    ]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path.replacingOccurrences(of: "/api/", with: "")
        let body = (try? JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())) ?? .null
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        if args.contains("--sticker-testing") {
            func jsonReply(_ value: JSONValue, _ status: Int = 200) throws -> (Data, HTTPURLResponse) {
                (try JSONEncoder().encode(value), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
            func stickerFile() -> JSONValue { .object(["id": .string("gifuploaded001"), "name": .string("PUBO-sticker.gif"), "mime": .string("image/gif"), "kind": .string("image"), "size": .number(Double(stickerUpload?.count ?? 0)), "hasPreview": .bool(true)]) }
            if path == "chat/attachments/create" {
                if args.contains("--sticker-upload-denied") { return try jsonReply(.object(["error": .object(["code": .string("CHAT_FIRST_MESSAGE_TEXT_ONLY")])]), 400) }
                let form = request.httpBody ?? Data()
                guard let boundary = request.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: "boundary=").last,
                      let start = form.range(of: Data("Content-Type: image/gif\r\n\r\n".utf8))?.upperBound,
                      let end = form.range(of: Data(("\r\n--" + boundary + "--").utf8), options: .backwards)?.lowerBound, start < end,
                      end - start <= GIFStickerCodec.byteLimit,
                      form.range(of: Data("name=\"toUserId\"\r\n\r\nsyntheticpeer\r\n".utf8)) != nil,
                      form.range(of: Data("name=\"i\"\r\n\r\nsynthetic-session\r\n".utf8)) != nil else { return try jsonReply(.object(["error": .object(["code": .string("INVALID_STICKER_UPLOAD")])]), 400) }
                stickerUpload = Data(form[start..<end]); return try jsonReply(stickerFile())
            }
            if path == "chat/attachments/gifuploaded001/original" {
                let allowed = request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-session"
                return (allowed ? stickerUpload ?? Data() : Data(), HTTPURLResponse(url: request.url!, statusCode: allowed ? 200 : 403, httpVersion: nil, headerFields: ["Content-Type": "image/gif"])!)
            }
            if path == "chat/messages/create-to-user", body["attachmentIds"].array.contains(.string("gifuploaded001")), stickerUpload != nil {
                counter += 1
                let note: JSONValue = .object(["id": .string("stickerreceipt\(counter)"), "fromUserId": Self.me["id"], "toUserId": Self.peer["id"], "text": body["text"], "attachments": .array([stickerFile()]), "clientMessageId": body["clientMessageId"], "createdAt": .string(ISO8601DateFormatter().string(from: Date())), "readState": .string("read")])
                sent.append(note); return try jsonReply(note)
            }
        }
        if args.contains("--gif-preview") {
            if path == "chat/messages/user-timeline" && sent.allSatisfy({ $0["id"].string != "gifmessage001" }) {
                let own = args.contains("--gif-own")
                let file: JSONValue = .object(["id": .string("gifattachment001"), "name": .string("PUBO-animation.gif"), "mime": .string(args.contains("--gif-static") ? "image/png" : "image/gif"), "kind": .string("image"), "size": .number(args.contains("--gif-too-large") ? 52_428_801 : Double(GIFTestFixtures.looping.count)), "width": .number(320), "height": .number(180), "hasPreview": .bool(true)])
                sent = [.object(["id": .string("gifmessage001"), "fromUserId": own ? Self.me["id"] : Self.peer["id"], "toUserId": own ? Self.peer["id"] : Self.me["id"], "text": .string("分享一张 GIF 动图"), "createdAt": .string("2026-11-03T10:00:00Z"), "revision": .number(0), "attachments": .array([file]), "readState": .string("read")])]
            }
            if path == "chat/messages/user-timeline", body["i"].string == "synthetic-second" {
                return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
            if path == "chat/attachments/gifattachment001/original" {
                gifReads += 1
                let revoked = args.contains("--gif-revoke-after-first") && gifReads > 1
                let recalled = sent.contains { $0["id"].string == "gifmessage001" && !$0["recalledAt"].isNull }
                let allowed = request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-session" && !revoked && !recalled
                let bytes = args.contains("--gif-corrupt") ? Data("GIF89a invalid fixture".utf8) : args.contains("--gif-finite") ? GIFTestFixtures.finite : args.contains("--gif-static") ? GIFTestFixtures.still : args.contains("--gif-large") ? GIFTestFixtures.large : GIFTestFixtures.looping
                return (allowed ? bytes : Data(), HTTPURLResponse(url: request.url!, statusCode: allowed ? 200 : 403, httpVersion: nil, headerFields: ["Content-Type": "image/gif"])!)
            }
        }
        #endif
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
        case "meta": response = .object(["maxNoteTextLength": .number(args.contains("--social-align") ? 60 : 3000), "name": .string("PUBO"), "disableRegistration": .bool(false), "emailRequiredForSignup": .bool(false)])
        case "emojis":
            #if DEBUG
            response = .object(["emojis": args.contains("--timeline-align") ? TimelineTestFixtures.snapshot["emojis"] : .array([])])
            #else
            response = .object(["emojis": .array([])])
            #endif
        case "i": response = body["i"].string == "synthetic-second" ? .object(["id": .string("syntheticsecond"), "username": .string("second"), "name": .string("第二个测试账号"), "chatScope": .string("mutual")]) : profile
        case "verification/show": response = .null
        case "admin/verification/list": response = .array([])
        case "admin/show-users": response = .array([profile, Self.peer])
        case "admin/announcements/list": response = .array(announcements)
        case "admin/announcements/create": counter += 1; var fields = body.object; fields.removeValue(forKey: "i"); fields["id"] = .string("adminannouncement\(counter)"); fields["isActive"] = .bool(true); response = .object(fields); announcements.append(response)
        case "invite/limit": response = .object(["remaining": .number(10)])
        case "invite/list": response = .array(invitations)
        case "invite/create": counter += 1; response = .object(["id": .string("invitation\(counter)"), "code": .string("SYNTHETIC-INVITE"), "usedBy": .null]); invitations.append(response)
        case "invite/delete": invitations.removeAll { $0["id"] == body["inviteId"] }; response = .null
        case "mute/list": response = .array(mutedUsers)
        case "mute/create": mutedUsers = [.object(["id": .string("muting1"), "mutee": Self.peer])]; response = .null
        case "mute/delete": mutedUsers = []; response = .null
        case "renote-mute/list", "blocking/list", "chat/blocking/list", "i/apps", "i/signin-history", "users/achievements", "i/webhooks/list": response = .array([])
        case "i/update": var values = profile.object; for (key, value) in body.object where key != "i" { values[key] = value }; profile = .object(values); response = profile
        case "signin-flow": response = .object(["finished": .bool(true), "i": .string("synthetic-session"), "id": .string("syntheticself")])
        case "signup": response = .object(["token": .string("synthetic-session"), "id": .string("syntheticself")])
        case "signup/request-phone-code": response = .null
        case "users/show": response = body["userIds"].isNull ? (body["userId"].string == "syntheticself" ? profile : Self.peer) : .array(body["userIds"].array.map { $0.string == "syntheticself" ? profile : Self.peer })
        case "users/search": response = .array([Self.peer])
        case "notes/search": response = .array(posts.filter { ($0["text"].string ?? "").localizedCaseInsensitiveContains(body["query"].string ?? "") })
        case "hashtags/search": response = .strings(["PUBO", "A2OLITE"])
        case "notes/search-by-tag": response = .array(posts)
        case "drive/folders": response = .array(driveFolders.filter { $0["parentId"] == body["folderId"] })
        case "drive/files": response = .array([driveFile])
        case "drive/files/show": response = driveFile
        case "drive/files/update": var value = driveFile.object; for key in ["name", "comment", "isSensitive", "folderId"] where body.object[key] != nil { value[key] = body[key] }; driveFile = .object(value); response = driveFile
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
            if args.contains("--timeline-align"), path != "users/notes" {
                var rows = posts.filter { body["untilId"].isNull || ($0["id"].string ?? "") < (body["untilId"].string ?? "") }
                if body["withFiles"].bool { rows = rows.filter { !$0["files"].array.isEmpty } }
                if body["withRenotes"] == .bool(false) { rows = rows.filter { !NoteContext.isRepost(Record($0)) } }
                if !body["withReplies"].bool { rows = rows.filter { $0["replyId"].isNull } }
                response = .array(Array(rows.prefix(body["limit"].int > 0 ? body["limit"].int : 20)))
            } else if args.contains("--refreshable-feed"), path != "users/notes" {
                timelineReads += 1
                let sample: JSONValue = .object(["id": .string(String(format: "refresh%08d", timelineReads)), "user": Self.me,
                    "text": .string("刷新样例 \(timelineReads)"), "cw": .null, "files": .array([]), "reactions": .object([:])])
                response = .array([sample] + posts)
            } else { response = .array(posts) }
        case "announcements": response = .array(announcements.filter { (body["display"].isNull || $0["display"] == body["display"]) && (body["isActive"].isNull || $0["isActive"] == body["isActive"]) })
        case "i/read-announcement": response = .null
        case "announcements/show": response = announcements.first { $0["id"] == body["announcementId"] } ?? .null
        case "admin/announcements/update":
            if !profile["isAdmin"].bool { status = 403; response = .object(["error": .object(["code": .string("PERMISSION_DENIED")])]) }
            else if let index = announcements.firstIndex(where: { $0["id"] == body["id"] }) { var value = announcements[index].object; for key in ["title", "text", "imageUrl"] { if let field = body.object[key] { value[key] = field } }; value["updatedAt"] = .string(ISO8601DateFormatter().string(from: Date())); announcements[index] = .object(value); response = .null }
        case "notes/drafts/list": response = .array(drafts.filter { $0["isActuallyScheduled"].bool == body["scheduled"].bool })
        case "notes/drafts/create":
            counter += 1; var value = body.object; value.removeValue(forKey: "i"); value["id"] = .string("draft\(counter)"); value["user"] = profile; value["files"] = .array(body["fileIds"].array.map { .object(["id": $0]) }); value["poll"] = .null
            drafts.append(.object(value)); response = .object(["createdDraft": .object(value)])
        case "notes/drafts/update":
            if let index = drafts.firstIndex(where: { $0["id"] == body["draftId"] }) { var value = drafts[index].object; value["scheduledAt"] = body["scheduledAt"]; value["isActuallyScheduled"] = body["isActuallyScheduled"]; drafts[index] = .object(value); response = .object(["updatedDraft": drafts[index]]) }
        case "music-charts/kpop-summary", "music-charts/kpop-chart":
            let key = body["chartKey"].string ?? "melon-top100"
            let chart = JSONValue.object(["chartKey": .string(key), "provider": .string(key == "genie-realtime" ? "genie" : "melon"), "label": .string(key == "genie-realtime" ? "Genie 实时榜" : "Melon TOP100"), "status": .string("available"), "rankBasis": .string("official_rank"), "coverage": .string("complete"), "sourceUrl": .string("https://www.melon.com/chart/index.htm"), "observedAt": .string("2026-11-01T15:00:00Z"), "lastSuccessAt": .string("2026-11-01T15:00:00Z")])
            let song = JSONValue.object(["songId": .string("fixturesong"), "title": .string("NEON"), "artists": .array([.object(["name": .string("A2O LITE")])]), "rank": .number(2), "bestRank7d": .number(1), "previousRank": .number(1), "change": .number(-1), "groupIds": .strings(["a2o-lite"]), "sourceMovement": .object(["type": .string(args.contains("--parity-preview") ? "unknown" : "same")])])
            let query = body["query"].string ?? ""; let group = body["groupId"].string ?? ""
            let matches = (query.isEmpty || "NEON A2O LITE".localizedCaseInsensitiveContains(query)) && (group.isEmpty || group == "a2o-lite")
            response = .object(["selected": chart, "chart": chart, "charts": .array([chart, .object(["chartKey": .string("genie-realtime"), "label": .string("Genie 实时榜")])]), "entries": .array(matches ? [song] : []), "total": .number(matches ? 1 : 0), "hasMore": .bool(false)])
            if args.contains("--home-motion") {
                if path == "music-charts/kpop-summary" { chartReads = body["_fixtureRefresh"].int }
                let changed = chartReads % 2 == 1
                let snapshot = PublicHomeSnapshot.value["summary"]
                var first = snapshot["entries"].array[0].object; first["rank"] = .number(changed ? 4 : 1); first["sourceMovement"] = .object(["type": .string(changed ? "down" : "same"), "amount": .number(changed ? 3 : 0)])
                var second = snapshot["entries"].array[1].object; second["rank"] = .number(changed ? 1 : 5); second["sourceMovement"] = .object(["type": .string(changed ? "up" : "same"), "amount": .number(changed ? 4 : 0)])
                var values = response.object
                if key == "melon-top100" { values["chart"] = snapshot["selected"]; values["selected"] = snapshot["selected"] }
                values["entries"] = .array([JSONValue.object(first), .object(second)].filter { (query.isEmpty || ($0["title"].string ?? "").localizedCaseInsensitiveContains(query)) && (group.isEmpty || $0["groupIds"].array.contains(.string(group))) })
                response = .object(values)
            }
        case "music-charts/kpop-history":
            response = .object(["basis": .string("observation"), "points": .array([.object(["observedAt": .string("2026-11-01T15:00:00Z"), "result": .string("ranked"), "rank": .number(1)])])])
            if args.contains("--home-motion") {
                var value = PublicHomeSnapshot.value["history"].object; value["songId"] = body["songId"]
                if body["songId"].string != "fixturesong" { value["points"] = .array([]) }
                response = .object(value)
            }
        case "notes/reactions/create", "notes/reactions/delete":
            if let index = posts.firstIndex(where: { $0["id"] == body["noteId"] }) {
                var value = posts[index].object; var reactions = posts[index]["reactions"].object
                if let old = posts[index]["myReaction"].string { let count = max(0,(reactions[old]?.int ?? 0)-1); if count == 0 { reactions.removeValue(forKey: old) } else { reactions[old] = .number(Double(count)) } }
                if path.hasSuffix("create"), let reaction = body["reaction"].string { reactions[reaction] = .number(Double((reactions[reaction]?.int ?? 0)+1)); value["myReaction"] = .string(reaction) } else { value["myReaction"] = .null }
                value["reactions"] = .object(reactions); posts[index] = .object(value)
            }; response = .null
        case "notes/show": response = posts.first { $0["id"] == body["noteId"] } ?? posts[0]
        case "notes/replies": response = .array([])
        case "notes/create":
            counter += 1
            let poll: JSONValue = body["poll"].isNull ? .null : .object(["choices": .array(body["poll"]["choices"].array.map { .object(["text": $0, "votes": .number(0), "isVoted": .bool(false)]) }), "multiple": body["poll"]["multiple"], "expiresAt": body["poll"]["expiresAt"].isNull ? .null : .string(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(body["poll"]["expiresAt"].int) / 1000)))])
            let note = JSONValue.object(["id": .string("newpost\(counter)"), "user": Self.me, "text": body["text"], "cw": body["cw"], "visibility": body["visibility"], "replyId": body["replyId"], "renoteId": body["renoteId"], "files": .array(body["fileIds"].array.map { .object(["id": $0, "name": .string("测试图片.png")]) }), "reactions": .object([:]), "poll": poll])
            var fields = note.object; fields["localOnly"] = body["localOnly"]; fields["visibleUserIds"] = body["visibleUserIds"]; fields["channelId"] = body["channelId"]
            let complete = JSONValue.object(fields); posts.insert(complete, at: 0); response = .object(["createdNote": complete])
            if args.contains("--lost-post-response") { throw URLError(.networkConnectionLost) }
        case "i/notifications":
            if args.contains("--social-align") {
                response = .array([
                    .object(["id": .string("socialnotice1"), "type": .string("chatRoomInvitationReceived"), "user": Self.peer, "invitation": .object(["room": rooms[0]]), "createdAt": .string("2026-11-03T10:00:00Z")]),
                    .object(["id": .string("socialnotice2"), "type": .string("achievementEarned"), "achievement": .string("notes1"), "createdAt": .string("2026-11-03T10:00:00Z")]),
                    .object(["id": .string("socialnotice3"), "type": .string("exportCompleted"), "fileId": .string("fixturefile"), "createdAt": .string("2026-11-03T10:00:00Z")])])
            } else { response = .array([.object(["id": .string("notice1"), "type": .string("follow"), "user": Self.peer, "isRead": .bool(false)])]) }
        case "notes/mentions": response = .array([.object(["id": .string("socialdirect"), "user": Self.peer, "text": .string("这是一条指定可见的帖子，不是聊天消息。"), "visibility": .string("specified")])])
        case "chat/conversation-settings/show": response = conversationPreference
        case "chat/conversation-settings/update":
            var values = conversationPreference.object
            if !body["isMuted"].isNull { values["isMuted"] = body["isMuted"] }
            if !body["pinned"].isNull { values["pinnedAt"] = body["pinned"].bool ? .string("2026-11-03T10:00:00Z") : .null }
            conversationPreference = .object(values); response = conversationPreference
        case "chat/conversations": response = .array([.object(["user": Self.peer, "lastMessage": .object(["id": .string("seedmessage"), "text": .string("点击开始聊天")]), "unreadCount": .number(0), "isMuted": .bool(false), "pinnedAt": .null])])
        case "chat/messages/user-timeline": response = .array(sent)
        case "chat/unread-summary": response = .object(["unreadCount": .number(12), "notificationUnreadCount": .number(args.contains("--parity-preview") ? 2 : 0), "hasNotificationLegacyUnread": .bool(false), "hasUnreadRoom": .bool(false)])
        case "chat/messages/context": response = .object(["messages": .array([oldMessage] + sent), "hasOlder": .bool(false), "hasNewer": .bool(true)])
        case "chat/messages/show": response = (sent + roomMessages).first { $0["id"] == body["messageId"] } ?? .null
        case "chat/messages/state":
            let ids = body["messageIds"].array.compactMap(\.string)
            let known = sent + (oldMessage.isNull ? [] : [oldMessage])
            response = .object(["messages": .array(known.filter { ids.contains($0["id"].string ?? "") }), "missingIds": .strings(ids.filter { id in !known.contains { $0["id"].string == id } })])
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
            }
            if let index = roomMessages.firstIndex(where: { $0["id"] == body["messageId"] }) {
                var value = roomMessages[index].object; var reactions = value["reactions"]?.array ?? []; let key = SocialContent.chatReactionKey(body["reaction"].string ?? "")
                if path.hasSuffix("/unreact") { reactions.removeAll { $0["user"]["id"] == Self.me["id"] && SocialContent.chatReactionKey($0["reaction"].string ?? "") == key } }
                else { reactions.append(.object(["user": Self.me, "reaction": .string(key)])) }
                value["reactions"] = .array(reactions); roomMessages[index] = .object(value)
            }; response = .null
        case "chat/messages/create-to-user":
            if let previous = sent.first(where: { $0["clientMessageId"] == body["clientMessageId"] }) { response = previous }
            else if (!sent.isEmpty && !args.contains("--social-align")) || args.contains("--reply-required") { status = 400; response = .object(["error": .object(["code": .string("CHAT_REPLY_REQUIRED")])]) }
            else {
                counter += 1
                response = .object(["id": .string("chat\(counter)"), "fromUserId": .string("syntheticself"), "toUserId": .string("syntheticpeer"), "text": body["text"], "attachments": .array([]), "clientMessageId": body["clientMessageId"], "readState": .string("unread")])
                sent.append(response)
                if args.contains("--lost-chat-response") { throw URLError(.networkConnectionLost) }
            }
        case "chat/attachments/create", "chat/attachments/import-drive": status = 400; response = .object(["error": .object(["code": .string("CHAT_FIRST_MESSAGE_TEXT_ONLY")])])
        default: response = try parityResponse(path, body) ?? .null
        }
        let data = try JSONEncoder().encode(response)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
    private func parityResponse(_ path: String, _ body: JSONValue) throws -> JSONValue? {
        if path == "drive" { return .object(["usage": .number(128), "driveUsage": .number(128), "chatUsage": .number(0), "reservedUsage": .number(0), "capacity": .number(104857600)]) }
        if path == "drive/folders/create" {
            counter += 1; let folder: JSONValue = .object(["id": .string("folder\(counter)"), "name": body["name"], "parentId": body["parentId"]]); driveFolders.append(folder); return folder
        }
        if path == "drive/folders/show" { return driveFolders.first { $0["id"] == body["folderId"] } ?? .null }
        if path == "drive/folders/update", let index = driveFolders.firstIndex(where: { $0["id"] == body["folderId"] }) { var value = driveFolders[index].object; for key in ["name", "parentId"] where body.object[key] != nil { value[key] = body[key] }; driveFolders[index] = .object(value); return driveFolders[index] }
        if path == "drive/folders/delete" { driveFolders.removeAll { $0["id"] == body["folderId"] }; return .null }
        if path == "chat/contact-groups/list" { return .array(contacts) }
        if path == "chat/contact-groups/create" { counter += 1; let value: JSONValue = .object(["id": .string("group\(counter)"), "name": body["name"], "userIds": .array([])]); contacts.append(value); return value }
        if path.hasPrefix("chat/contact-groups/"), let index = contacts.firstIndex(where: { $0["id"] == body["groupId"] }) {
            var value = contacts[index].object
            if path.hasSuffix("/update") { value["name"] = body["name"] }
            if path.hasSuffix("/add-user") { value["userIds"] = .array(contacts[index]["userIds"].array + [body["userId"]]) }
            if path.hasSuffix("/remove-user") { value["userIds"] = .array(contacts[index]["userIds"].array.filter { $0 != body["userId"] }) }
            contacts[index] = .object(value)
            if path.hasSuffix("/delete") { contacts.remove(at: index) }; return .null
        }
        if path == "chat/rooms/create" { counter += 1; var value = body.object; value.removeValue(forKey: "i"); value["id"] = .string("room\(counter)"); value["ownerId"] = Self.me["id"]; rooms.append(.object(value)); return .object(value) }
        if path == "chat/rooms/owned" { return .array(rooms) }
        if path == "chat/rooms/joining" { return .array(rooms.map { .object(["id": $0["id"], "room": $0]) }) }
        if path == "chat/rooms/invitations/inbox" { return .array([]) }
        if path == "chat/rooms/show" { return rooms.first { $0["id"] == body["roomId"] } ?? .null }
        if path == "chat/rooms/members" { return .array([.object(["id": .string("membership"), "user": profile])]) }
        if path == "chat/messages/create-to-room" { counter += 1; var value = body.object; value.removeValue(forKey: "i"); value["id"] = .string("roommessage\(counter)"); value["fromUserId"] = Self.me["id"]; value["fromUser"] = profile; roomMessages.append(.object(value)); if ProcessInfo.processInfo.arguments.contains("--lost-room-response") { throw URLError(.networkConnectionLost) }; return .object(value) }
        if path == "chat/messages/room-timeline" { return .array(roomMessages.filter { $0["toRoomId"] == body["roomId"] }.reversed()) }
        if path == "chat/messages/search" { return .array((sent + roomMessages).filter { ($0["text"].string ?? "").contains(body["query"].string ?? "") }) }
        if path == "notes/featured" { return .array(posts) }
        if path == "notes/reactions" { return .array([.object(["id": .string("reaction1"), "user": Self.peer, "type": .string("❤️")])]) }
        for kind in CollectionKind.allCases {
            let rows = collections[kind.rawValue] ?? []
            if path == kind.base + "/create" { counter += 1; var value = body.object; value.removeValue(forKey: "i"); value["id"] = .string("collection\(counter)"); value["userId"] = Self.me["id"]; value["user"] = profile; collections[kind.rawValue] = rows + [.object(value)]; return .object(value) }
            if path == kind.base + "/show" { return rows.first { $0["id"] == body[kind.idKey] } ?? .null }
            if path == kind.base + "/list" || path == kind.base + "/owned" || (kind == .gallery && path == "users/gallery/posts") { return .array(rows) }
            if path == kind.base + "/update", let index = rows.firstIndex(where: { $0["id"] == body[kind.idKey] }) {
                var updated = rows; var fields = rows[index].object; for (key, value) in body.object where key != "i" && key != kind.idKey { fields[key] = value }; updated[index] = .object(fields); collections[kind.rawValue] = updated; return updated[index]
            }
            if path == kind.base + "/delete" { collections[kind.rawValue] = rows.filter { $0["id"] != body[kind.idKey] }; return .null }
            if path == kind.feed { return .array(posts) }
        }
        return nil
    }
}
