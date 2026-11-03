import SwiftUI
import PUBOCore

struct AdminRoleCondition: View {
    @Binding var value: JSONValue
    private let types = ["isLocal", "isRemote", "isSuspended", "isLocked", "isBot", "isCat", "isExplorable", "roleAssignedTo", "createdLessThan", "createdMoreThan", "followersLessThanOrEq", "followersMoreThanOrEq", "followingLessThanOrEq", "followingMoreThanOrEq", "notesLessThanOrEq", "notesMoreThanOrEq", "and", "or", "not"]
    private let labels = ["isLocal":"本站用户", "isRemote":"外站用户", "isSuspended":"已封禁", "isLocked":"关注需批准", "isBot":"Bot", "isCat":"猫模式", "isExplorable":"允许被发现", "roleAssignedTo":"已分配角色", "createdLessThan":"注册时间少于", "createdMoreThan":"注册时间超过", "followersLessThanOrEq":"粉丝数不超过", "followersMoreThanOrEq":"粉丝数不少于", "followingLessThanOrEq":"关注数不超过", "followingMoreThanOrEq":"关注数不少于", "notesLessThanOrEq":"帖子数不超过", "notesMoreThanOrEq":"帖子数不少于", "and":"同时满足全部条件", "or":"满足任意条件", "not":"不满足此条件"]
    private var type: String { value["type"].string ?? "isLocal" }
    var body: some View {
        Form {
            Picker("条件", selection: Binding(get: { type }, set: reset)) { ForEach(types, id: \.self) { Text(labels[$0] ?? $0).tag($0) } }
            if ["and", "or"].contains(type) {
                ForEach(Array(value["values"].array.indices), id: \.self) { index in
                    NavigationLink("条件 \(index + 1)") { AnyView(AdminRoleCondition(value: Binding(get: { value["values"].array.indices.contains(index) ? value["values"].array[index] : .null }, set: { var rows = value["values"].array; guard rows.indices.contains(index) else { return }; rows[index] = $0; set("values", .array(rows)) }))) }
                }.onDelete { indexes in var rows = value["values"].array; rows.remove(atOffsets: indexes); set("values", .array(rows)) }
                Button("添加条件") { var rows = value["values"].array; rows.append(Self.initial()); set("values", .array(rows)) }
            } else if type == "not" { NavigationLink("不满足的条件") { AnyView(AdminRoleCondition(value: binding("value"))) } }
            else if type == "roleAssignedTo" { AdminValueField(key: "roleId", schema: .object(["type": .string("string")]), value: binding("roleId")) }
            else if type.hasPrefix("created") { AdminValueField(key: "秒数", schema: .object(["type": .string("number"), "minimum": .number(0)]), value: binding("sec")) }
            else if type.contains("ThanOrEq") { AdminValueField(key: "数量", schema: .object(["type": .string("number"), "minimum": .number(0)]), value: binding("value")) }
        }.puboForm().navigationTitle("自动分配条件").onAppear { if value["type"].isNull { value = Self.initial() } }
    }
    static func initial() -> JSONValue { .object(["id": .string(UUID().uuidString), "type": .string("isLocal")]) }
    private func set(_ key: String, _ item: JSONValue) { var copy = value.object; copy[key] = item; value = .object(copy) }
    private func binding(_ key: String) -> Binding<JSONValue> { Binding(get: { value[key] }, set: { set(key, $0) }) }
    private func reset(_ type: String) {
        var fields: [String: JSONValue] = ["id": value["id"].isNull ? .string(UUID().uuidString) : value["id"], "type": .string(type)]
        if ["and", "or"].contains(type) { fields["values"] = .array([Self.initial()]) }
        else if type == "not" { fields["value"] = Self.initial() }
        else if type == "roleAssignedTo" { fields["roleId"] = .string("") }
        else if type.hasPrefix("created") { fields["sec"] = .number(86400) }
        else if type.contains("ThanOrEq") { fields["value"] = .number(0) }
        value = .object(fields)
    }
}
