import Foundation

public enum Endpoint {
    public static let origin = URL(string: "https://bolubo.com")!

    public static func api(_ path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(".."),
              path.range(of: "^[a-zA-Z0-9/_-]+$", options: .regularExpression) != nil else {
            throw APIError(code: "INVALID_ENDPOINT", message: "接口地址无效")
        }
        return origin.appendingPathComponent("api").appendingPathComponent(path)
    }

    public static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "bolubo.com" &&
        (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
}

public struct APIError: Error, LocalizedError, Equatable, Sendable {
    public let code: String
    public let message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
    public var errorDescription: String? { message }
}
