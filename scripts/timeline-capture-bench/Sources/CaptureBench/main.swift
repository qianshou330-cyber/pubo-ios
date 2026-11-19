import Foundation
import PUBOCore

// No copied capturedIDs implementation. The timed active=true path is the app's
// expression; stream.captureNotes and all SwiftUI/layout/network work are excluded.
@inline(never) func filteredCapture(_ notes: [Record], _ visibleIDs: Set<String>) -> Set<String> {
    TimelinePresentation.capturedIDs(notes.filter { visibleIDs.contains($0.id) })
}
@inline(never) func selectedCapture(_ selected: [Record]) -> Set<String> {
    TimelinePresentation.capturedIDs(selected)
}
@inline(never) func noOpControl(_ expected: Set<String>) -> Set<String> { expected }
var checksum: UInt64 = 0
@inline(never) func consume(_ ids: Set<String>) {
    // Observable consumption prevents a count-only dead-result benchmark. Identical
    // cost exists in each arm; report control separately, never subtract it.
    for id in ids { checksum &+= UInt64(id.utf8.count) }
}
struct RNG: RandomNumberGenerator {
    var state: UInt64 = 0xC77020261119
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
func nested(_ base: String, depth: Int = 0) -> JSONValue {
    var object: [String: JSONValue] = ["id": .string("\(base)-d\(depth)")]
    if depth < 4 { object["reply"] = nested(base, depth: depth + 1) }
    if depth == 0 { object["renote"] = .object(["id": .string(base + "-renote")]) }
    return .object(object)
}
struct Fixture {
    let count: Int
    let state: TimelineState
    let notes: [Record]
    let visible: [Set<String>]
    let selected: [[Record]]
    let expected: [Set<String>]
    init(_ count: Int) {
        let records = (0..<count).map { Record(nested(String(format: "synthetic-%04d", $0))) }
        let indexes = (0..<8).map { $0 * (count / 8) }
        let selections = [0, 1].map { shift in indexes.map { records[$0 + shift] } }
        let expectedIDs = [0, 1].map { shift in
            Set(indexes.flatMap { index -> [String] in
                let base = String(format: "synthetic-%04d", index + shift)
                return (0..<4).map { "\(base)-d\($0)" } + [base + "-renote"]
            })
        }
        self.count = count
        var current = TimelineState()
        current.page(records, older: false, preferences: TimelinePreferences(), accountID: nil)
        state = current
        notes = current.notes; selected = selections
        visible = selections.map { Set($0.map(\.id)) }; expected = expectedIDs
    }
}
let fixtures = [20, 200, 2000].map(Fixture.init)
let arms = ["filter-plus-capturedIDs", "capturedIDs-only-8", "noop-return-same-set", "experimental-binary-plus-capturedIDs"]
let warmupRounds = 5, rounds = 40, operationsPerBatch = 100
func operation(_ fixture: Fixture, arm: String, variant: Int) -> Set<String> {
    switch arm {
    case "filter-plus-capturedIDs": return filteredCapture(fixture.notes, fixture.visible[variant])
    case "capturedIDs-only-8": return selectedCapture(fixture.selected[variant])
    case "experimental-binary-plus-capturedIDs": return fixture.state.experimentalCapturedIDs(visibleIDs: fixture.visible[variant])
    case "noop-return-same-set": return noOpControl(fixture.expected[variant])
    default: preconditionFailure("Unknown arm")
    }
}
// Correctness prerequisite, outside measurement: exact identities include depth3,
// exclude depth4, and include renote references. Both visible sets contain eight.
for fixture in fixtures {
    for variant in 0...1 {
        precondition(fixture.visible[variant].count == 8 && fixture.expected[variant].count == 40)
        for arm in arms { precondition(operation(fixture, arm: arm, variant: variant) == fixture.expected[variant]) }
    }
}
var rng = RNG()
var rows: [[String: Any]] = []
var order: [[String: Any]] = []
for round in -warmupRounds..<rounds {
    let cases = fixtures.indices.flatMap { i in arms.map { (i, $0) } }.shuffled(using: &rng)
    for (position, item) in cases.enumerated() {
        let (index, arm) = item
        let start = DispatchTime.now().uptimeNanoseconds
        for invocation in 0..<operationsPerBatch {
            consume(operation(fixtures[index], arm: arm, variant: invocation % 2))
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if round >= 0 {
            rows.append(["round": round, "position": position, "loadedRecords": fixtures[index].count,
                         "visibleRecords": 8, "arm": arm, "batchNanoseconds": elapsed,
                         "operations": operationsPerBatch, "nanosecondsPerOperation": Double(elapsed) / Double(operationsPerBatch)])
        }
        order.append(["round": round, "position": position, "loadedRecords": fixtures[index].count, "arm": arm])
    }
}
func stats(_ values: [Double]) -> [String: Any] {
    let s = values.sorted(), n = values.count
    let median = n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2 : s[n/2]
    return ["samples": n, "medianNanosecondsPerOperation": median,
            "p95NanosecondsPerOperation": s[max(0, Int(ceil(Double(n) * 0.95)) - 1)],
            "p95Definition": "nearest rank across batch means, not per-event tail latency"]
}
var summaries: [[String: Any]] = []
for fixture in fixtures {
    for arm in arms {
        let matching = rows.filter { ($0["loadedRecords"] as? Int) == fixture.count && ($0["arm"] as? String) == arm }
        var summary = stats(matching.compactMap { $0["nanosecondsPerOperation"] as? Double })
        summary["loadedRecords"] = fixture.count; summary["visibleRecords"] = 8; summary["arm"] = arm
        summaries.append(summary)
    }
}
let report: [String: Any] = [
    "schemaVersion": 2, "status": "MEASURED_HOST_ONLY", "smoothnessAcceptance": "NOT_EVALUATED",
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "warmupRounds": warmupRounds, "rounds": rounds, "operationsPerBatch": operationsPerBatch,
    "seed": "0xC77020261119", "clock": "DispatchTime.uptimeNanoseconds", "checksum": checksum,
    "summaries": summaries, "raw": rows, "orderIncludingWarmup": order,
    "scope": "Active path, fixed eight visible records. Timed consumption overhead retained in every arm. No control subtraction. Fresh fixtures allocated outside timer. Not UIKit, stream subscriptions, SwiftUI, Simulator or iPhone hitches. No pass threshold."
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
