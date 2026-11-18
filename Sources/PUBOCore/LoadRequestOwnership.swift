import Foundation

/// A request's right to release a busy indicator, independent of content epochs.
/// Invalidating a view permits a new request without letting the old completion
/// clear that new request's busy state. Use on the owning view's actor only.
public struct LoadRequestOwnership {
    private var current: UUID?
    public init() {}
    public var isLoading: Bool { current != nil }
    public mutating func begin() -> UUID? {
        guard current == nil else { return nil }
        let token = UUID(); current = token; return token
    }
    public mutating func finish(_ token: UUID) {
        if current == token { current = nil }
    }
    public mutating func invalidate() { current = nil }
}
