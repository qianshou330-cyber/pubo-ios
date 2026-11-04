#if DEBUG
import Foundation
import PUBOCore

enum TimelineTestFixtures {
    static let snapshot: JSONValue = {
        guard let url = Bundle.main.url(forResource: "TimelineParity", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }; return value
    }()
    static func media(_ url: URL) -> Data? {
        guard url.host == "timeline-fixture.invalid" else { return nil }
        if url.path.hasSuffix(".png") { return GIFTestFixtures.still }
        return url.path.contains("finite") ? GIFTestFixtures.finite : GIFTestFixtures.looping
    }
}
#endif
