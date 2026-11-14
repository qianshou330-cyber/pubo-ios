import Foundation

/// One ordering domain for cache reads, writes and deletion. Snapshot encoding
/// runs off the caller thread; synchronous deletion drains earlier writes so a
/// queued snapshot cannot recreate an account after logout has returned.
public final class OrderedSnapshotQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "pubo.cache.snapshots", qos: .utility)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var revisions: [String: UUID] = [:]
    public init() {}

    public func sync<T>(_ operation: () throws -> T) rethrows -> T {
        try queue.sync(execute: operation)
    }

    public func cancelPending() {
        lock.lock(); generation &+= 1; revisions.removeAll(); lock.unlock()
    }

    public func submit(key: String, operation: @escaping () -> Void) {
        lock.lock()
        let epoch = generation, revision = UUID()
        revisions[key] = revision
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            let current = generation == epoch && revisions[key] == revision
            if current { revisions.removeValue(forKey: key) }
            lock.unlock()
            guard current else { return }
            operation()
        }
    }
}
