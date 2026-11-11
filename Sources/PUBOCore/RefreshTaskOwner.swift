import Foundation

/// A user-requested refresh belongs to the visible screen, not the transient
/// framework callback used by UIRefreshControl. The screen explicitly cancels
/// this owner when it leaves or changes account/feed context.
@MainActor
public final class RefreshTaskOwner {
    private var task: Task<Void, Never>?
    private var revision = 0
    public init() {}

    public func run(_ operation: @escaping @MainActor () async -> Void) async {
        if let task { await task.value; return }
        revision += 1
        let current = revision
        let newTask = Task { await operation() }
        task = newTask
        await newTask.value
        if revision == current { task = nil }
    }

    public func cancel() {
        revision += 1
        task?.cancel()
        task = nil
    }
}
