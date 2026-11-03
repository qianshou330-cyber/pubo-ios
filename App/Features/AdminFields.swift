import SwiftUI
import PUBOCore

enum AdminLabels {
    static let fields: [String: String] = ["id":"记录编号", "userId":"用户", "username":"用户名", "name":"名称", "description":"说明", "text":"正文", "title":"标题", "reason":"原因", "note":"管理备注", "comment":"备注", "contact":"联系方式", "type":"类别", "status":"状态", "state":"状态", "sort":"排序", "query":"筛选", "search":"搜索", "limit":"每页数量", "offset":"起始位置", "untilId":"此前记录编号", "sinceId":"此后记录编号", "sinceDate":"起始时间", "untilDate":"结束时间", "host":"服务器域名", "hostname":"服务器域名", "origin":"来源", "email":"邮箱", "password":"密码", "token":"令牌", "fileId":"文件", "folderId":"文件夹", "roleId":"角色", "roleIds":"适用角色", "emojiId":"表情", "emojiIds":"表情列表", "url":"地址", "imageUrl":"图片地址", "iconUrl":"图标地址", "color":"颜色", "isSensitive":"敏感内容", "localOnly":"仅限本站", "aliases":"别名", "category":"分组", "license":"使用许可", "isPublic":"公开", "isModerator":"授予版主权限", "isAdministrator":"授予管理员权限", "isExplorable":"可在探索中展示", "asBadge":"显示角色徽章", "displayOrder":"显示顺序", "target":"分配方式", "condFormula":"自动分配条件", "policies":"角色策略", "canEditMembersByModerator":"允许版主管理成员", "preserveAssignmentOnMoveAccount":"迁移后保留角色", "expiresAt":"到期时间", "count":"数量", "expirationDate":"有效期", "display":"显示方式", "isActive":"有效公告", "isRead":"已读", "needConfirmationToRead":"要求确认已读", "forExistingUsers":"仅面向已有用户", "silence":"静默", "queue":"队列", "jobId":"任务编号", "forward":"转发举报", "applicationId":"认证申请", "documentId":"认证材料", "approvedType":"认证类别", "reviewReason":"审核说明", "isSuspended":"封禁", "isBlocked":"阻止联邦通信", "isSilenced":"限制曝光", "isNSFW":"敏感服务器", "deliveryMode":"投递方式", "requestId":"请求编号", "reportId":"举报", "webhookId":"Webhook", "recipientId":"接收者", "active":"启用", "events":"触发事件", "headers":"请求头", "endpoint":"服务地址", "secret":"密钥", "provider":"验证服务", "sitekey":"公开站点标识", "captchaResult":"官方验证结果", "instanceUrl":"服务地址", "priority":"优先级", "ratio":"展示比例", "place":"位置", "startsAt":"开始时间", "memo":"管理备注", "nameContains":"名称包含", "isRemote":"来自外站", "hostnameContains":"域名包含", "withoutSensitive":"排除敏感内容", "markAsSensitive":"标记敏感", "resolved":"已处理", "assigneeId":"处理人", "forwarded":"已转发"]
    static func title(_ key: String) -> String { fields[key] ?? key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression) }
    static func value(_ value: JSONValue) -> String {
        switch value { case .string(let text): return text; case .number(let number): return number.formatted(); case .bool(let flag): return flag ? "是" : "否"; case .null: return "未设置"; case .array(let values): return "\(values.count) 项"; case .object(let values): return "\(values.count) 项设置" }
    }
}

/// Native typed form controls. Nested objects and arrays remain editable without a JSON console.
struct AdminValueField: View {
    let key: String
    let schema: JSONValue
    @Binding var value: JSONValue
    var secret = false
    @State private var numberText = ""
    @State private var userPicker = false
    @State private var filePicker = false
    private var title: String { AdminLabels.title(key) }
    private var imageURL: Bool { ["imageUrl", "iconUrl", "bannerUrl", "backgroundImageUrl", "logoImageUrl", "app192IconUrl", "app512IconUrl", "faviconUrl"].contains(key) }
    var body: some View {
        Group {
            if key == "condFormula" {
                NavigationLink("自动分配条件") { AdminRoleCondition(value: $value) }
            } else if !schema["enum"].array.isEmpty {
                Picker(title, selection: $value) { ForEach(schema["enum"].array, id: \.self) { Text(AdminLabels.value($0)).tag($0) } }
            } else if value.isNull && schema["nullable"].bool {
                HStack { Text(title); Spacer(); Button("设置内容") { var definition = schema.object; definition["nullable"] = .bool(false); value = AdminSchema.initial(.object(definition)) } }
            } else {
                field
                if schema["nullable"].bool { Button("将“\(title)”设为空") { value = .null }.font(.caption) }
            }
        }.sheet(isPresented: $userPicker) { UserPicker { value = .string($0.id) } }
            .sheet(isPresented: $filePicker) { DrivePicker(imagesOnly: imageURL) { file in value = imageURL ? file["url"] : .string(file.id) } }
    }
    @ViewBuilder private var field: some View {
        switch schema["type"].string {
        case "boolean": Toggle(title, isOn: Binding(get: { value.bool }, set: { value = .bool($0) }))
        case "number", "integer":
            if ["startsAt", "expiresAt"].contains(key) { DatePicker(title, selection: Binding(get: { if let date = puboDate(value.string) { return date }; return Date(timeIntervalSince1970: Double(value.int) / 1000) }, set: { value = .number($0.timeIntervalSince1970 * 1000) }), displayedComponents: [.date, .hourAndMinute]) }
            else { TextField(title, text: $numberText).keyboardType(.numbersAndPunctuation).onAppear { if case .number(let number) = value { numberText = number.rounded() == number ? String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), number) : String(number) } }.onChange(of: numberText) { _, text in value = Double(text).map(JSONValue.number) ?? .string(text) } }
        case "array": NavigationLink { AdminArrayEditor(title: title, schema: schema, value: $value) } label: { LabeledContent(title, value: "\(value.array.count) 项") }
        case "object": NavigationLink { AdminObjectEditor(title: title, schema: schema, value: $value) } label: { LabeledContent(title, value: "\(value.object.count) 项") }
        default:
            if secret || AdminSchema.isSecret(key) { SecureField(title + "（修改时填写）", text: Binding(get: { value.string ?? "" }, set: { value = .string($0) })).textInputAutocapitalization(.never).autocorrectionDisabled() }
            else {
                TextField(title, text: Binding(get: { value.string ?? "" }, set: { value = .string($0) }), axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                if ["userId", "assigneeId"].contains(key) { Button("选择用户") { userPicker = true } }
                if key == "fileId" { Button("从网盘选择文件") { filePicker = true } }
                if imageURL { Button("从网盘选择图片") { filePicker = true } }
            }
        }
    }
}

struct AdminObjectEditor: View {
    let title: String
    let schema: JSONValue
    @Binding var value: JSONValue
    @State private var newKey = ""
    @State private var newType = "string"
    private var keys: [String] { Array(Set(schema["properties"].object.keys).union(value.object.keys)).sorted() }
    var body: some View {
        Form {
            ForEach(keys, id: \.self) { key in
                let definition = schema["properties"].object[key] ?? inferred(value[key])
                if value.object[key] != nil {
                    AdminValueField(key: key, schema: definition, value: Binding(get: { value[key] }, set: { var copy = value.object; copy[key] = $0; value = .object(copy) }))
                    if !schema["required"].array.contains(.string(key)) { Button("移除“\(AdminLabels.title(key))”", role: .destructive) { var copy = value.object; copy.removeValue(forKey: key); value = .object(copy) } }
                } else { Button("设置“\(AdminLabels.title(key))”") { var copy = value.object; copy[key] = AdminSchema.initial(definition); value = .object(copy) } }
            }
            if schema["properties"].object.isEmpty {
                Section("添加项目") {
                    TextField("项目名称", text: $newKey).textInputAutocapitalization(.never)
                    Picker("内容类型", selection: $newType) { Text("文字").tag("string"); Text("数字").tag("number"); Text("开关").tag("boolean"); Text("列表").tag("array"); Text("设置组").tag("object") }
                    Button("添加项目") { var copy = value.object; copy[newKey] = AdminSchema.initial(.object(["type": .string(newType)])); value = .object(copy); newKey = "" }.disabled(newKey.isEmpty || value.object[newKey] != nil || newKey == "i")
                }
            }
        }.puboForm().navigationTitle(title)
    }
    private func inferred(_ value: JSONValue) -> JSONValue { let type: String; switch value { case .object: type = "object"; case .array: type = "array"; case .bool: type = "boolean"; case .number: type = "number"; default: type = "string" }; return .object(["type": .string(type), "nullable": .bool(value.isNull)]) }
}

struct AdminArrayEditor: View {
    let title: String
    let schema: JSONValue
    @Binding var value: JSONValue
    var body: some View {
        List {
            ForEach(Array(value.array.indices), id: \.self) { index in
                AdminValueField(key: "第 \(index + 1) 项", schema: schema["items"], value: Binding(get: { value.array.indices.contains(index) ? value.array[index] : .null }, set: { var items = value.array; guard items.indices.contains(index) else { return }; items[index] = $0; value = .array(items) }))
            }.onDelete { indices in var items = value.array; items.remove(atOffsets: indices); value = .array(items) }
                .onMove { source, destination in var items = value.array; items.move(fromOffsets: source, toOffset: destination); value = .array(items) }
            Button("添加项目") { var items = value.array; items.append(AdminSchema.initial(schema["items"])); value = .array(items) }.disabled(schema.object["maxItems"] != nil && value.array.count >= schema["maxItems"].int)
        }.puboForm().navigationTitle(title).toolbar { EditButton() }
    }
}
