#if DEBUG
import Foundation
import PUBOCore

enum TimelineTestFixtures {
    static let snapshot: JSONValue = {
        guard let url = Bundle.main.url(forResource: "TimelineParity", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }; return value
    }()
    static func media(_ url: URL) -> Data? {
        guard url.host == "timeline-fixture.invalid" else { return nil }
        if url.path.hasSuffix(".apng") { return PublicAnimationFixtures.apng }
        if url.path.hasSuffix(".webp") { return PublicAnimationFixtures.webp }
        if url.path.hasSuffix(".png") { return GIFTestFixtures.still }
        return url.path.contains("finite") ? GIFTestFixtures.finite : GIFTestFixtures.looping
    }
    static var posts: [JSONValue] {
        let format = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--timeline-format=") }?.components(separatedBy: "=").last
        return snapshot["posts"].array.map { original in
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
