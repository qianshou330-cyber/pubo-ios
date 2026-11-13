#if DEBUG
import Foundation
import PUBOCore

enum TimelineTestFixtures {
    static let snapshot: JSONValue = {
        guard let url = Bundle.main.url(forResource: "TimelineParity", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }; return value
    }()
    static func media(_ url: URL) -> Data? {
        guard url.host == "timeline-fixture.invalid" else { return nil }
        if url.path == "/avatar.png" { return GIFTestFixtures.avatar }
        if url.path.hasSuffix(".apng") { return PublicAnimationFixtures.apng }
        if url.path.hasSuffix(".webp") { return PublicAnimationFixtures.webp }
        if url.path.hasSuffix(".png") { return GIFTestFixtures.still }
        return url.path.contains("finite") ? GIFTestFixtures.finite : GIFTestFixtures.looping
    }
    static var posts: [JSONValue] {
        let format = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--timeline-format=") }?.components(separatedBy: "=").last
        let grid = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--timeline-grid=") }?.components(separatedBy: "=").last.flatMap(Int.init)
        return snapshot["posts"].array.map { original in
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
