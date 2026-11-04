#if DEBUG
import Foundation
import PUBOCore

enum TimelineTestFixtures {
    static func media(_ url: URL) -> Data? {
        guard url.host == "timeline-fixture.invalid" else { return nil }
        return GIFTestFixtures.looping
    }
}
#endif
