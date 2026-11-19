#if DEBUG && PUBO_SPARSE_WORLD_PROBE
import UIKit
import PUBOCore

enum SparseFixture {
    static let flag = "--sparse-world-probe"
    static let nonce = ProcessInfo.processInfo.environment["PUBO_SPARSE_NONCE"] ?? ""
    static var enabled: Bool {
        let a = ProcessInfo.processInfo.arguments
        return UUID(uuidString: nonce) != nil && a.contains("--ui-testing") && a.contains("--timeline-align") &&
            a.contains(flag) && !a.contains("--isolated-backend") && !a.contains("--timeline-persistence")
    }
    static func id(_ n: Int) -> String { String(format: "w80-%04d", n) }
    static func ids(_ n: Int) -> [String] {
        guard n > 0 && n <= 200 else { return [] }
        return ((201 - n)...200).reversed().map(id)
    }
    static let knownOuter = Set(ids(200))
    static func posts() -> [JSONValue] {
        let user: JSONValue = .object(["id":.string("syntheticpeer"), "name":.string("样例"),
                                      "username":.string("fixture"), "host":.null])
        func raw(_ id: String, text: String) -> [String:JSONValue] {
            ["id": .string(id), "text": .string(text), "createdAt": .string("2026-11-04T00:00:00.000Z"),
             "userId": .string("syntheticpeer"), "user": user, "visibility": .string("public"), "files": .array([]),
             "fileIds": .array([]), "cw": .null, "replyId": .null, "renoteId": .null, "reactions": .object([:])]
        }
        var inner = raw("w80-shared",text:"共享引用")
        inner["replyId"] = .string("w80-leaf"); inner["reply"] = .object(raw("w80-leaf",text:"共享原帖"))
        return (1...200).reversed().map { n in
            var row = raw(id(n), text:"样例 \(n)\n第二行正文。\n第三行正文。")
            row["renoteId"] = .string("w80-shared"); row["renote"] = .object(inner)
            return .object(row)
        }
    }

    // Synthetic pagination only. Never log arbitrary request bodies, credentials or external records.
    private static let lock = NSLock()
    private static var pages: [[String:Any]] = []
    private static var bad = false
    static func didServe(path: String, body: JSONValue, result: JSONValue) {
        guard enabled, path == "notes/local-timeline", body["limit"].int == 20 else { return }
        let cursor = body["untilId"].string ?? ""
        let resultIDs = result.array.compactMap { $0["id"].string }
        lock.lock(); defer { lock.unlock() }
        let i = pages.count
        guard i < 10, cursor == (i == 0 ? "" : id(201-i*20)),
              body["withRenotes"] == .bool(true), body["withReplies"] == .bool(false), body["withFiles"] == .bool(false),
              resultIDs == Array(ids(200)[(20*i)..<(20*i+20)]) else { bad = true; return }
        pages.append(["cursor":cursor,"ids":resultIDs])
    }
    static func pageReceipt() -> ([[String:Any]], Bool) {
        lock.lock(); defer { lock.unlock() }; return (pages,bad)
    }
}

@MainActor enum SparseObserver {
    private static var context: String?
    static private(set) var ready = false
    private static var invalid = false
    private static var events: [[String:Any]] = []
    private static var drags: [Double] = []
    private static var merged: [[String:Any]] = []
    private static var slot: (visible: Set<String>, oracle: Set<String>, t: Double)?
    private static var previous: Set<String>?
    private static var receiving = 0
    private static let arm = "pubo.sparse.arm", branch = "pubo.sparse.branch"
    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    static func start(_ ctx: String) -> Bool {
        guard SparseFixture.enabled else { return false }
        guard context == nil else { invalid = true; return false }
        context = ctx; return true
    }
    static func mergedPage(_ state: TimelineState, _ ctx: String) -> Bool {
        let count = (merged.count+1)*20
        guard context == ctx, count <= 200, state.notes.map(\.id) == SparseFixture.ids(count),
              state.pending.isEmpty, state.olderCursor == SparseFixture.id(201-count) else { invalid = true; return false }
        merged.append(["count":count,"oldest":SparseFixture.id(201-count)])
        if count == 200 {
            let (pages,bad) = SparseFixture.pageReceipt()
            ready = pages.count == 10 && !bad && !invalid
            if !ready { invalid = true }
        }
        return true
    }
    static func enter(_ feed: TimelineState, _ visible: Set<String>, _ active: Bool, _ ctx: String) {
        guard ready && active else { return }
        guard ctx == context, feed.notes.count == 200, slot == nil, events.count < 384 else { invalid = true; return }
        let dict = Thread.current.threadDictionary
        guard dict[arm] == nil, dict[branch] == nil else { invalid = true; return }
        // Oracle is diagnostic overhead, not a speed measurement. Do not clamp visible.
        let oracle = TimelinePresentation.capturedIDs(feed.notes.filter { visible.contains($0.id) })
        guard visible.isSubset(of: SparseFixture.knownOuter) else { invalid = true; return }
        slot = (visible,oracle,now); receiving = 0; dict[arm] = true
    }
    static func received(_ input: Set<String>, stored: Set<String>, owner: String) {
        guard let s = slot else { return }
        receiving += 1
        let actual = Thread.current.threadDictionary[branch] as? String ?? "unobserved"
        let added = previous.map { s.visible.subtracting($0).sorted() } ?? []
        let removed = previous.map { $0.subtracting(s.visible).sorted() } ?? []
        let allowed = s.visible.union(["w80-shared","w80-leaf"])
        guard input.isSubset(of: allowed), stored.isSubset(of: allowed), s.oracle.isSubset(of: allowed),
              owner == "timeline", receiving == 1 else { invalid = true; return }
        events.append(["i":events.count+1,"t":s.t,"branch":actual,"outer":s.visible.sorted(),
                       "added":added,"removed":removed,"input":input.sorted(),"stored":stored.sorted(),"oracle":s.oracle.sorted()])
        if input != s.oracle || stored != input || actual != (s.visible.isEmpty || s.visible.count > 8 ? "filter" : "binary") {
            invalid = true
        }
        previous = s.visible
    }
    static func leave() {
        if slot != nil && receiving != 1 { invalid = true }
        slot = nil
        Thread.current.threadDictionary.removeObject(forKey: arm)
        Thread.current.threadDictionary.removeObject(forKey: branch)
    }
    static func drag(_ movement: CGSize, ctx: String) {
        guard ready, ctx == context, -movement.height >= 60, abs(movement.width) < abs(movement.height) else { return }
        if drags.count >= 4 { invalid = true; return }
        drags.append(now)
    }
    static func saveInactive() {
        guard SparseFixture.enabled, context != nil else { return }
        let (pages,bad) = SparseFixture.pageReceipt()
        let data: [String:Any] = ["schema":1,"nonce":SparseFixture.nonce,"recordedAt":now,"ready":ready,"invalid":invalid || bad,
                                  "scope":"instrumented synthetic simulator only","pages":pages,"merged":merged,"events":events,"drags":drags]
        do {
            let bytes = try JSONSerialization.data(withJSONObject:data,options:[.sortedKeys])
            try bytes.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("pubo-sparse-"+SparseFixture.nonce+".json"),
                            options:.atomic)
        } catch { /* Collector treats an absent receipt as UNAVAILABLE. */ }
    }
}
#endif
