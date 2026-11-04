import AuthenticationServices
import UIKit
import PUBOCore

@MainActor final class WebAuthorization: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var activeID: String?
    func cancel() {
        session?.cancel()
        if let identifier = activeID { finish(identifier, result: nil, error: CancellationError()) }
    }
    func login(api: APIClient) async throws -> String {
        guard session == nil else { throw APIError(code: "AUTH_BUSY", message: "请先完成当前授权。") }
        let identifier = UUID().uuidString
        activeID = identifier
        defer { session = nil; continuation = nil; activeID = nil }
        var url = URLComponents(string: "https://bolubo.com/miauth/\(identifier)")!
        let permissions = ["read:account", "write:account", "read:blocks", "write:blocks", "read:drive", "write:drive", "read:following", "write:following", "write:notes", "read:notifications", "write:notifications", "read:reactions", "write:reactions", "read:chat", "write:chat", "write:report-abuse", "read:favorites", "write:favorites", "write:votes", "read:channels", "write:channels", "read:gallery", "write:gallery", "read:gallery-likes", "write:gallery-likes", "read:mutes", "write:mutes", "read:invite-codes", "write:invite-codes"]
        url.queryItems = [URLQueryItem(name: "name", value: "PUBO iPhone"), URLQueryItem(name: "callback", value: "pubonative://auth"), URLQueryItem(name: "permission", value: permissions.joined(separator: ","))]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "pubonative") { [weak self] result, error in
                Task { @MainActor in self?.finish(identifier, result: result, error: error) }
            }
            session?.presentationContextProvider = self
            session?.prefersEphemeralWebBrowserSession = false
            if session?.start() != true { finish(identifier, result: nil, error: APIError(code: "AUTH_UNAVAILABLE", message: "无法打开安全登录窗口。")) }
        }
        guard callback.scheme == "pubonative", callback.host == "auth", URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "session" })?.value == identifier else { throw APIError.invalidResponse }
        let result = try await api.call("miauth/\(identifier)/check")
        guard result["ok"].bool, let token = result["token"].string else { throw APIError(code: "AUTH_INCOMPLETE", message: "授权未完成，请重试。") }
        return token
    }
    private func finish(_ identifier: String, result: URL?, error: Error?) {
        guard activeID == identifier, let pending = continuation else { return }
        continuation = nil
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            pending.resume(throwing: APIError(code: "AUTH_CANCELLED", message: "已取消网页授权，可以继续登录。"))
        }
        else if let error { pending.resume(throwing: error) }
        else if let result { pending.resume(returning: result) }
        else { pending.resume(throwing: APIError.invalidResponse) }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

