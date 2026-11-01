import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class DenyRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 120
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: DenyRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }
}

public actor APIClient {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }

    public func call(_ path: String, body: [String: JSONValue] = [:], token: String? = nil, mutation: Bool = false) async throws -> JSONValue {
        var fields = body
        fields.removeValue(forKey: "i")
        if let token { fields["i"] = .string(token) }
        var request = URLRequest(url: try Endpoint.api(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(fields))
        return try await execute(request, mutation: mutation)
    }

    public func upload(path: String, data: Data, filename: String, mime: String, fields: [String: String], token: String) async throws -> JSONValue {
        guard data.count <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "首版单个上传文件最多 50 MB；服务器可能有更低限制。") }
        var request = URLRequest(url: try Endpoint.api(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        let boundary = "PUBO-" + UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var form = Data()
        func append(_ text: String) { form.append(Data(text.utf8)) }
        var safeFields = fields
        safeFields["i"] = token
        for key in safeFields.keys.sorted() {
            guard key.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil else { throw APIError.invalidResponse }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(safeFields[key]!)\r\n")
        }
        let safeName = filename.replacingOccurrences(of: "[\r\n\"\\\\]", with: "_", options: .regularExpression)
        let safeMime = mime.range(of: "^[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+$", options: .regularExpression) != nil ? mime : "application/octet-stream"
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(safeMime)\r\n\r\n")
        form.append(data)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = form
        return try await execute(request, mutation: true)
    }

    public func privateAttachment(id: String, token: String) async throws -> Data {
        guard id.range(of: "^[a-zA-Z0-9]{1,32}$", options: .regularExpression) != nil else { throw APIError.invalidResponse }
        var request = URLRequest(url: try Endpoint.api("chat/attachments/\(id)/original"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else { throw APIError(code: "ATTACHMENT_UNAVAILABLE", message: "附件不可用或没有访问权限。") }
        guard data.count <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "附件超过本客户端预览上限。") }
        return data
    }

    private func execute(_ request: URLRequest, mutation: Bool) async throws -> JSONValue {
        guard let url = request.url, Endpoint.isTrusted(url) else { throw APIError.invalidResponse }
        do {
            let (data, response) = try await transport.send(request)
            let parsed = try? JSONDecoder().decode(JSONValue.self, from: data)
            guard (200..<300).contains(response.statusCode) else {
                if mutation && response.statusCode >= 500 { throw APIError.uncertain }
                let known = ["SMS_RATE_LIMITED", "INVALID_SMS_CODE", "PHONE_VERIFICATION_REQUIRED", "PHONE_ALREADY_BOUND", "INVALID_PHONE_NUMBER", "SMS_NOT_CONFIGURED", "SMS_SEND_FAILED"]
                let rawMessage = parsed?["error"]["message"].string ?? parsed?["message"].string ?? parsed?["error"].string
                let code = parsed?["error"]["code"].string ?? known.first(where: { rawMessage == $0 || rawMessage == "Error: " + $0 }) ?? "HTTP_\(response.statusCode)"
                throw APIError(code: code, message: APIError.message(for: code, status: response.statusCode))
            }
            if data.isEmpty { return .null }
            guard let parsed else { throw mutation ? APIError.uncertain : APIError.invalidResponse }
            return parsed
        } catch let error as APIError { throw error }
        catch {
            if mutation { throw APIError.uncertain }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw APIError(code: "NETWORK_ERROR", message: "网络连接失败，请检查网络后重试。")
        }
    }
}

public extension APIError {
    static let invalidResponse = APIError(code: "INVALID_RESPONSE", message: "服务器响应异常，请稍后重试。")
    static let uncertain = APIError(code: "OUTCOME_UNKNOWN", message: "服务器处理结果尚未确认。请先核对记录，勿重复发送。")
    static func message(for code: String, status: Int) -> String {
        switch code {
        case "CHAT_REPLY_REQUIRED": return "对方未回复之前只能发送一条消息，等对方回复以后才可以继续留言"
        case "CHAT_FIRST_MESSAGE_TEXT_ONLY": return "对方回复前仅支持发送一条文字消息"
        case "CHAT_CLIENT_UPGRADE_REQUIRED": return "请更新客户端后再发送私信附件。"
        case "PERMISSION_DENIED": return "当前授权缺少此功能权限，请到“我的”重新授权；原有草稿会保留。"
        case "MESSAGE_CONFLICT": return "消息已在其他设备更新，请核对最新内容。你的编辑文字已保留。"
        case "EDIT_WINDOW_EXPIRED": return "消息发送已超过 24 小时，不能再编辑。"
        case "MESSAGE_NOT_EDITABLE": return "这条消息当前不能编辑。"
        case "ALREADY_VOTED": return "此选项已投过票，请更新票数。"
        case "ALREADY_EXPIRED": return "投票已结束。"
        case "NATIVE_PUSH_DISABLED": return "本站锁屏推送通道尚未开放。"
        case "NATIVE_PUSH_DEVICE_LIMIT": return "这个账号登记的推送设备已达上限，请先在旧设备关闭推送。"
        case "NATIVE_PUSH_SCOPE_REQUIRED": return "当前授权缺少通知权限，请到“我的”重新授权。"
        case "NATIVE_PUSH_ENVIRONMENT_MISMATCH": return "安装包的推送环境与本站配置不匹配，请检查签名和分发版本。"
        case "NATIVE_PUSH_STALE_OPERATION": return "已忽略较旧的设备登记操作，请确认设备时间后重新开启通知。"
        case "SMS_RATE_LIMITED": return "验证码请求过于频繁，请稍后再试。"
        case "INVALID_SMS_CODE": return "短信验证码不正确或已过期，请重新获取。"
        case "PHONE_VERIFICATION_REQUIRED": return "请填写手机号和短信验证码。"
        case "PHONE_ALREADY_BOUND": return "这个手机号已绑定账号，请使用原账号登录。"
        case "INVALID_PHONE_NUMBER": return "请输入有效的中国大陆手机号码。"
        case "SMS_NOT_CONFIGURED", "SMS_SEND_FAILED": return "短信暂时无法发送，请稍后再试。"
        case "YOU_HAVE_BEEN_BLOCKED", "BLOCKED", "CHAT_PERMISSION_DENIED": return "当前无法向对方发送消息，请检查接收范围和屏蔽关系。"
        case "CHAT_ATTACHMENT_REJECTED": return "附件被拒绝，请检查类型、大小、剩余空间及聊天权限。"
        case "INVALID_TOKEN", "AUTHENTICATION_FAILED", "CREDENTIAL_REQUIRED": return "登录已失效，请重新登录。"
        case "RATE_LIMIT_EXCEEDED", "TOO_MANY_AUTHENTICATION_FAILURES": return "操作过于频繁，请稍后再试。"
        default:
            switch status {
            case 401: return "登录信息或验证码不正确，请重新检查。"
            case 403: return "当前操作被拒绝，请检查账号状态和权限。"
            case 429: return "操作过于频繁，请稍后再试。"
            case 404: return "内容不存在或当前不可访问。"
            default: return "操作未完成（\(code)），请检查输入后重试。"
            }
        }
    }
}
