#if DEBUG
import Foundation
import PUBOCore

/// CI-only loopback transport. No production token, cookies, or remote fallback.
struct IsolatedTransport: HTTPTransport {
    private let underlying = URLSessionTransport()
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let original = request.url, Endpoint.isTrusted(original), original.path.hasPrefix("/api/") else { throw APIError.invalidResponse }
        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)!
        components.scheme = "http"; components.host = "127.0.0.1"; components.port = 61812
        var local = request; local.url = components.url
        return try await underlying.send(local)
    }
}
#endif
