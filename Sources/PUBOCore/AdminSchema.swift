import Foundation

public struct AdminEndpoint: Codable, Identifiable, Sendable {
    public let id: String
    public let schema: JSONValue
    public let requireAdmin: Bool
    public let requireModerator: Bool
    public let requiredRolePolicy: String
    public let secure: Bool
    public let kind: String
    public let mutation: Bool
    public func available(to account: JSONValue) -> Bool {
        if requireAdmin && !account["isAdmin"].bool { return false }
        if requireModerator && !account["isAdmin"].bool && !account["isModerator"].bool { return false }
        if !requiredRolePolicy.isEmpty && !account["policies"][requiredRolePolicy].bool { return false }
        return account["isAdmin"].bool || account["isModerator"].bool || (!requiredRolePolicy.isEmpty && account["policies"][requiredRolePolicy].bool)
    }
}

public enum AdminSchema {
    public static func identity(_ key: String, record: JSONValue, source: String, context: [String: JSONValue]) -> JSONValue? {
        if let direct = record.object[key] { return direct }
        if key == "userId", let user = record["user"]["id"].string { return .string(user) }
        if let inherited = context[key] { return inherited }
        let recordID = record.object["id"]
        switch key {
        case "userId": return record["username"].string != nil || source == "admin/show-user" || source == "admin/show-users" ? recordID : nil
        case "roleId": return source.hasPrefix("admin/roles/") && !source.hasSuffix("/users") ? recordID : nil
        case "applicationId": return source.contains("verification/") ? recordID : nil
        case "reportId": return source.contains("abuse-user-report") ? recordID : nil
        case "fileId": return source.contains("drive/") ? recordID : nil
        case "emojiId": return source.contains("emoji/") ? recordID : nil
        case "jobId": return source.contains("queue/") ? recordID : nil
        default: return nil
        }
    }
    /// Use the first identity alternative for forms (for example emoji ID); keep full validation below.
    public static func form(_ schema: JSONValue) -> JSONValue {
        var properties = schema["properties"].object
        var required = Set(schema["required"].array.compactMap(\.string))
        var parts = schema["allOf"].array
        if let first = (schema["anyOf"].array + schema["oneOf"].array).first { parts.append(first) }
        for part in parts { let merged = form(part); properties.merge(merged["properties"].object) { _, new in new }; required.formUnion(merged["required"].array.compactMap(\.string)) }
        var result = schema.object; result["properties"] = .object(properties); result["required"] = .strings(required.sorted())
        if !properties.isEmpty { result["type"] = .string("object") }
        return .object(result)
    }
    public static func initial(_ schema: JSONValue) -> JSONValue {
        if let value = schema.object["default"] { return value }
        if let choice = schema["enum"].array.first { return choice }
        switch schema["type"].string {
        case "boolean": return .bool(false)
        case "integer", "number": return schema.object["minimum"] ?? .number(0)
        case "array": return .array([])
        case "object": return .object(Dictionary(uniqueKeysWithValues: schema["required"].array.compactMap(\.string).map { ($0, initial(schema["properties"][$0])) }))
        default: return schema["nullable"].bool ? .null : .string("")
        }
    }
    /// Validate before submission; the server remains authoritative for permissions and formats.
    public static func validate(_ value: JSONValue, schema: JSONValue, path: String = "表单") throws {
        if value.isNull && schema["nullable"].bool { return }
        for part in schema["allOf"].array { try validate(value, schema: part, path: path) }
        let alternatives = schema["anyOf"].array + schema["oneOf"].array
        if !alternatives.isEmpty {
            guard alternatives.contains(where: { (try? validate(value, schema: $0, path: path)) != nil }) else { throw invalid(path, "格式不符合要求") }
        }
        if !schema["enum"].array.isEmpty && !schema["enum"].array.contains(value) { throw invalid(path, "请选择有效选项") }
        switch (schema["type"].string, value) {
        case ("object", .object(let fields)):
            for key in schema["required"].array.compactMap(\.string) where fields[key] == nil { throw invalid(path + "." + key, "必填") }
            for (key, field) in fields {
                if let child = schema["properties"].object[key] { try validate(field, schema: child, path: path + "." + key) }
                else if schema["additionalProperties"] == .bool(false) { throw invalid(path + "." + key, "不支持此字段") }
            }
        case ("array", .array(let items)):
            if let minimum = schema.object["minItems"], items.count < minimum.int { throw invalid(path, "数量不足") }
            if let maximum = schema.object["maxItems"], items.count > maximum.int { throw invalid(path, "数量超过限制") }
            if schema["uniqueItems"].bool && Set(items).count != items.count { throw invalid(path, "项目不能重复") }
            for (index, item) in items.enumerated() { try validate(item, schema: schema["items"], path: path + "[\(index + 1)]") }
        case ("string", .string(let string)):
            if let minimum = schema.object["minLength"], string.unicodeScalars.count < minimum.int { throw invalid(path, "内容过短") }
            if let maximum = schema.object["maxLength"], string.unicodeScalars.count > maximum.int { throw invalid(path, "内容过长") }
            if let pattern = schema["pattern"].string, let expression = try? NSRegularExpression(pattern: pattern), expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) == nil { throw invalid(path, "格式不正确") }
        case ("number", .number(let number)), ("integer", .number(let number)):
            guard number.isFinite, schema["type"].string != "integer" || number.rounded() == number else { throw invalid(path, "请填写有效整数") }
            if case .number(let minimum) = schema["minimum"], number < minimum { throw invalid(path, "低于最小值") }
            if case .number(let maximum) = schema["maximum"], number > maximum { throw invalid(path, "超过最大值") }
        case ("boolean", .bool): break
        case (nil, _): break
        default: throw invalid(path, "数据类型不正确")
        }
    }
    public static func changes(_ values: [String: JSONValue], original: JSONValue, identityKeys: Set<String>) -> [String: JSONValue] {
        values.filter { identityKeys.contains($0.key) || original[$0.key] != $0.value }
    }
    public static func isSecret(_ key: String) -> Bool {
        let name = key.lowercased()
        return name.contains("password") || name.contains("secret") || name.contains("token") || name.contains("privatekey") || name.contains("accesskey") || name.contains("apikey") || name.contains("authkey") || name.contains("backupcode") || name == "smtppass" || name == "data" || name == "headers"
    }
    public static func redacted(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let fields): return .object(fields.mapValues { redacted($0) }.filter { !isSecret($0.key) })
        case .array(let items): return .array(items.map(redacted))
        default: return value
        }
    }
    public static func bulkResults(operation: String, fields: [String: JSONValue], rows: [JSONValue]) -> [String: Bool] {
        let expected = JSONValue.object(fields)
        return Dictionary(uniqueKeysWithValues: Set(expected["ids"].array.compactMap(\.string)).map { id in
            let row = rows.first { $0["id"].string == id }
            if operation == "delete-bulk" { return (id, row == nil) }
            guard let row else { return (id, false) }
            let aliases = Set(expected["aliases"].array.compactMap(\.string)), actual = Set(row["aliases"].array.compactMap(\.string))
            switch operation {
            case "set-category-bulk": return (id, row["category"] == expected["category"])
            case "set-license-bulk": return (id, row["license"] == expected["license"])
            case "set-aliases-bulk": return (id, actual == aliases)
            case "add-aliases-bulk": return (id, aliases.isSubset(of: actual))
            case "remove-aliases-bulk": return (id, aliases.isDisjoint(with: actual))
            default: return (id, false)
            }
        })
    }
    private static func invalid(_ path: String, _ message: String) -> APIError { APIError(code: "INVALID_ADMIN_FORM", message: path + "：" + message) }
}
