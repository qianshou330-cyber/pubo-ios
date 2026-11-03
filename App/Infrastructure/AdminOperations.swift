import Foundation
import CryptoKit
import PUBOCore

struct AdminReadRequest {
    let path: String
    var fields: [String: JSONValue] = [:]
    var match: (String, JSONValue)?
}

enum AdminOperations {
    static let identities: Set<String> = ["id", "userId", "roleId", "applicationId", "reportId", "fileId", "emojiId", "host", "inbox", "queue", "jobId", "webhookId"]
    static func defaults(_ endpoint: AdminEndpoint) -> [String: JSONValue] {
        let schema = AdminSchema.form(endpoint.schema)
        var values = AdminSchema.initial(schema).object
        for (key, field) in schema["properties"].object where field.object["default"] != nil { values[key] = field["default"] }
        if schema["properties"].object["limit"] != nil { values["limit"] = .number(30) }
        return values
    }
    static func seed(_ record: JSONValue, for endpoint: AdminEndpoint, context: [String: JSONValue] = [:]) -> [String: JSONValue] {
        let properties = AdminSchema.form(endpoint.schema)["properties"].object
        var result = defaults(endpoint)
        for key in properties.keys {
            if let supplied = context[key] { result[key] = supplied }
            if let value = record.object[key], !AdminSchema.isSecret(key) { result[key] = value }
            if ["userId", "roleId", "applicationId", "reportId", "fileId", "emojiId", "webhookId", "jobId"].contains(key), record.object["id"] != nil { result[key] = record["id"] }
        }
        if endpoint.id == "admin/update-user-note" { result["text"] = record["moderationNote"] }
        return result
    }
    /// Every editable object with a read endpoint gets re-read before submission.
    static func snapshot(_ id: String, fields: [String: JSONValue]) -> AdminReadRequest? {
        let value = JSONValue.object(fields)
        if id == "admin/update-meta" || id == "admin/roles/update-default-policies" { return .init(path: "admin/meta") }
        if id == "admin/captcha/save" { return .init(path: "admin/captcha/current") }
        if id.hasPrefix("admin/verification/"), let target = value["applicationId"].string, !target.isEmpty { return .init(path: "admin/verification/show", fields: ["applicationId": .string(target)]) }
        if id.hasPrefix("admin/roles/"), let target = value["roleId"].string, !target.isEmpty { return .init(path: "admin/roles/show", fields: ["roleId": .string(target)]) }
        if id.hasPrefix("admin/system-webhook/"), let target = value["id"].string, !target.isEmpty { return .init(path: "admin/system-webhook/show", fields: ["id": .string(target)]) }
        if id.hasPrefix("admin/abuse-report/notification-recipient/"), let target = value["id"].string, !target.isEmpty { return .init(path: "admin/abuse-report/notification-recipient/show", fields: ["id": .string(target)]) }
        if id.contains("federation/"), let host = value["host"].string, !host.isEmpty { return .init(path: "federation/show-instance", fields: ["host": .string(host)]) }
        if ["drive/files/update", "drive/files/delete"].contains(id), let target = value["fileId"].string, !target.isEmpty { return .init(path: "admin/drive/show-file", fields: ["fileId": .string(target)]) }
        for category in ["announcements", "ad", "avatar-decorations", "emoji"] where id.hasPrefix("admin/" + category + "/") {
            if let target = value["id"].string, !target.isEmpty { return .init(path: "admin/" + category + "/list", fields: category == "announcements" ? ["status": .string("all")] : [:], match: ("id", .string(target))) }
        }
        if let target = value["userId"].string, !target.isEmpty, !id.contains("assign"), !id.contains("/create") { return .init(path: "admin/show-user", fields: ["userId": .string(target)]) }
        if let target = value["reportId"].string, !target.isEmpty { return .init(path: "admin/abuse-user-reports", fields: ["state": .string("all")], match: ("id", .string(target))) }
        return nil
    }
    @MainActor static func read(_ request: AdminReadRequest, session: AppSession) async throws -> JSONValue {
        var fields = request.fields; var seen = Set<String>()
        repeat {
            if request.match != nil { fields["limit"] = .number(100) }
            let result = try await session.admin.call(session: session, path: request.path, fields: fields)
            guard let (key, target) = request.match else { return result }
            guard case .array(let rows) = result else { throw APIError.invalidResponse }
            if let match = rows.first(where: { $0[key] == target }) { return match }
            guard rows.count == 100, let cursor = rows.last?["id"].string, seen.insert(cursor).inserted else { throw APIError(code: "ADMIN_ITEM_GONE", message: "记录已不存在或不再可访问，请返回列表核对。") }
            fields["untilId"] = .string(cursor)
            try Task.checkCancellation()
        } while true
    }
    static func comparable(_ record: JSONValue, endpoint: String) -> JSONValue {
        if endpoint == "admin/roles/update-default-policies" { return .object(["policies": record["policies"]]) }
        if endpoint == "admin/update-user-note" { var values = record.object; values["text"] = record["moderationNote"]; return .object(values) }
        return record
    }
    static func payload(_ endpoint: AdminEndpoint, values: [String: JSONValue], original: JSONValue) -> [String: JSONValue] {
        guard !original.isNull else { return values }
        let id = endpoint.id
        if id.hasSuffix("/update") || ["admin/update-meta", "admin/update-user-note", "admin/roles/update-default-policies", "drive/files/update"].contains(id) {
            var changes = AdminSchema.changes(values, original: comparable(original, endpoint: id), identityKeys: identities)
            // These legacy endpoints require complete fields; preserve even hidden secrets explicitly.
            if ["admin/system-webhook/update", "admin/abuse-report/notification-recipient/update"].contains(id) {
                for key in AdminSchema.form(endpoint.schema)["properties"].object.keys where changes[key] == nil {
                    if let value = original.object[key] { changes[key] = value }
                }
            }
            return changes
        }
        return values
    }
    static func pendingKey(_ id: String) -> String { "admin-pending-" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func effect(_ id: String) -> String {
        if id.contains("delete") || id.contains("cleanup") || id.contains("clean-") || id.contains("/clear") { return "将删除所选记录或清理指定范围的数据。删除操作可能无法撤销。" }
        if id.contains("suspend") { return "将改变此用户或实例的访问、发布或联邦通信状态。" }
        if id.contains("roles/") { return "将改变角色或权限，可能影响多个用户。" }
        if id.contains("queue/") { return "将改变指定队列或任务的执行状态，可能影响正在处理的工作。" }
        if id.contains("update-meta") || id.contains("captcha/") { return "将保存站点设置，可能影响所有用户的访问或服务连接。" }
        if id.contains("verification/") { return "将改变此申请的认证状态，服务器会记录本次审核。" }
        if id.contains("send-email") || id.contains("webhook/test") || id.contains("forward") { return "将向所选接收者发送一次信息。请先核对接收目标。" }
        return "将把当前表单提交给 PUBO。请核对目标记录与修改内容。"
    }
}
