#if DEBUG
import Foundation
import PUBOCore

enum TimelineTestFixtures {
    static let snapshot: JSONValue = {
        guard let url = Bundle.main.url(forResource: "TimelineParity", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }; return value
    }()
    static func media(_ url: URL) -> Data? {
        guard url.host == "timeline-fixture.invalid" else { return nil }
        if url.path == "/broken-poster" { return Data() }
        if url.path == "/avatar.png" { return GIFTestFixtures.avatar }
        if url.path.hasSuffix(".apng") { return PublicAnimationFixtures.apng }
        if url.path.hasSuffix(".webp") { return PublicAnimationFixtures.webp }
        if url.path.hasSuffix(".png") { return GIFTestFixtures.still }
        return url.path.contains("finite") ? GIFTestFixtures.finite : GIFTestFixtures.looping
    }
    // Independent synthetic page-2 diagnostic. Do not grant access to arbitrary
    // hosts, paths or query strings. A dedicated key avoids ambiguity with page 1.
    static let page2Argument = "--world-page2-poster"
    static let page2URL = "https://timeline-fixture.invalid/poster-red.mp4?sample=world-page2-0001"
    static var page2Enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--timeline-align") &&
            args.contains(page2Argument) && !args.contains("--isolated-backend") &&
            !args.contains(where: { $0.hasPrefix("--video-poster-fixture=") })
    }
    /// Call only after the actor witnessed the actual default first-page response.
    /// Never replace a first-page, reconnect (limit 100), notes/show or other reply.
    static func page2Response(_ response: JSONValue, body: [String: JSONValue], path: String,
                              sawSeed: inout Bool) -> JSONValue {
        guard page2Enabled, path == "notes/local-timeline",
              body["limit"] == .number(20), body["withFiles"] == .bool(false),
              body["withReplies"] == .bool(false), body["withRenotes"] == .bool(true) else { return response }
        let ids = response.array.compactMap { $0["id"].string }
        let seedIDs = (5...25).reversed().filter { $0 != 19 }.map { String(format: "at4tltest%04d", $0) }
        if body["untilId"] == nil || body["untilId"] == .null {
            sawSeed = ids == seedIDs && response.array.count == seedIDs.count
            return response
        }
        let expected = ["at4tltest0004", "at4tltest0003", "at4tltest0002", "at4tltest0001"]
        guard sawSeed, body["untilId"] == .string("at4tltest0005"), ids == expected,
              response.array.count == expected.count else { return response }
        var rows = response.array
        var note = rows[3].object
        let id = "worldpage2poster0001"
        let video: JSONValue = .object(["id": .string(id), "type": .string("video/mp4"),
            "url": .string(page2URL), "thumbnailUrl": .null, "isSensitive": .bool(false),
            "properties": .object(["width": .number(160), "height": .number(90)])])
        note["files"] = .array([video]); note["fileIds"] = .array([.string(id)])
        rows[3] = .object(note)
        return .array(rows)
    }
    static func videoSource(_ url: URL?) -> URL? {
        if page2Enabled {
            guard url?.absoluteString == page2URL else { return nil }
            return Bundle.main.url(forResource: "PublicPosterRedFixture", withExtension: "mp4")
        }
        guard ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--video-poster-fixture=") }),
              url?.host == "timeline-fixture.invalid", url?.path == "/poster-red.mp4" else { return nil }
        return Bundle.main.url(forResource: "PublicPosterRedFixture", withExtension: "mp4")
    }
    static var posts: [JSONValue] {
        let format = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--timeline-format=") }?.components(separatedBy: "=").last
        let grid = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--timeline-grid=") }?.components(separatedBy: "=").last.flatMap(Int.init)
        return snapshot["posts"].array.map { original in
            if original["id"].string == "at4tltest0025",
               let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--video-poster-fixture=") })?.components(separatedBy: "=").last {
                var note = original.object
                let thumb: JSONValue = mode == "thumbnail" ? .string("https://timeline-fixture.invalid/still.png") : mode == "broken" ? .string("https://timeline-fixture.invalid/broken-poster") : .null
                let file: JSONValue = .object(["id": .string("posterfixture"), "type": .string("video/mp4"), "url": .string(mode == "untrusted" ? "https://external.invalid/poster.mp4" : "https://timeline-fixture.invalid/poster-red.mp4"), "thumbnailUrl": thumb, "isSensitive": .bool(false), "properties": .object(["width": .number(160), "height": .number(90)])])
                note["files"] = .array([file]); note["fileIds"] = .array([.string("posterfixture")])
                return .object(note)
            }
            if ProcessInfo.processInfo.arguments.contains("--timeline-visual-header"), original["id"].string == "at4tltest0025",
               let url = Bundle.main.url(forResource: "TimelineVisualCases", withExtension: "json"),
               let data = try? Data(contentsOf: url), let fixture = try? JSONDecoder().decode(JSONValue.self, from: data) {
                var note = original.object, user = original["user"].object
                user["name"] = fixture["headerName"]; user["username"] = fixture["headerUsername"]
                note["user"] = .object(user); note["text"] = fixture["text"]; note["visibility"] = fixture["visibility"]
                return .object(note)
            }
            if original["id"].string == "at4tltest0022", let grid, (2...5).contains(grid) {
                var note = original.object
                let files: [JSONValue] = (1...grid).map { index in var file = original["files"].array[0].object; file["id"] = .string("timelineimage\(index)"); return .object(file) }
                note["files"] = .array(files); note["fileIds"] = .array(files.map { $0["id"] })
                return .object(note)
            }
            guard original["id"].string == "at4tltest0024", let format, ["finite", "apng", "webp"].contains(format) else { return original }
            var note = original.object; var file = original["files"].array[0].object
            let ext = format == "finite" ? "gif" : format
            file["type"] = .string("image/" + ext); file["url"] = .string("https://timeline-fixture.invalid/" + format + "." + ext)
            file["thumbnailUrl"] = file["url"]; note["files"] = .array([.object(file)])
            return .object(note)
        }
    }
}
#endif
