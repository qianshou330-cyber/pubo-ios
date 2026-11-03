import SwiftUI
import PUBOCore

struct NotificationPreferencesView: View {
    @Environment(AppSession.self) private var session
    @State private var original: JSONValue = .null
    @State private var configs: [String: JSONValue] = [:]
    @State private var emailTypes = Set<String>()
    @State private var lists: [Record] = []
    @State private var busy = false
    @State private var error: String?
    private let names = [("follow", "关注"), ("mention", "提及"), ("reply", "回复"), ("renote", "转发"), ("quote", "引用"), ("reaction", "反应"), ("pollEnded", "投票结束"), ("receiveFollowRequest", "关注申请"), ("chatRoomInvitationReceived", "群聊邀请"), ("scheduledNotePosted", "定时发布成功"), ("scheduledNotePostFailed", "定时发布失败"), ("app", "应用通知"), ("achievementEarned", "获得成就"), ("login", "新登录"), ("createToken", "创建授权令牌")]
    private let modes = [("all", "所有用户"), ("following", "我关注的用户"), ("follower", "关注我的用户"), ("mutualFollow", "互相关注"), ("followingOrFollower", "关注任一方"), ("list", "指定列表"), ("never", "不接收")]
    private let simple = Set(["app", "achievementEarned", "login", "createToken", "scheduledNotePosted", "scheduledNotePostFailed"])
    var body: some View {
        Form {
            Text("此处修改服务器通知偏好，会与 H5 同步。当前锁屏推送通道的开放状态保持不变。").font(.footnote)
            if original.isNull { ProgressView("读取通知设置…") }
            ForEach(names, id: \.0) { key, title in
                Section(title) {
                    Picker("接收范围", selection: Binding(get: { configs[key]?["type"].string ?? "all" }, set: { configs[key] = .object(["type": .string($0)]) })) {
                        ForEach(modes.filter { !simple.contains(key) || ["all", "never"].contains($0.0) }, id: \.0) { Text($0.1).tag($0.0) }
                    }.accessibilityIdentifier("notification.preference." + key)
                    if configs[key]?["type"].string == "list" {
                        Picker("用户列表", selection: Binding(get: { configs[key]?["userListId"].string ?? "" }, set: { configs[key] = .object(["type": .string("list"), "userListId": .string($0)]) })) {
                            Text("请选择列表").tag(""); ForEach(lists) { Text($0.displayName).tag($0.id) }
                        }
                        if lists.isEmpty { Text("请先在“更多功能 → 列表”中创建列表。") }
                    }
                }.disabled(original.isNull || busy)
            }
            Section("邮件通知") { ForEach(names.filter { ["mention", "reply", "quote", "follow", "receiveFollowRequest"].contains($0.0) }, id: \.0) { key, title in Toggle(title, isOn: Binding(get: { emailTypes.contains(key) }, set: { if $0 { emailTypes.insert(key) } else { emailTypes.remove(key) } })) }.disabled(original.isNull || busy) }
            Button("保存通知偏好") { Task { await save() } }.disabled(busy || original.isNull)
            if let error { Text(error).foregroundStyle(.secondary) }
        }.puboForm().navigationTitle("通知偏好").task { await load() }
    }
    private func load() async {
        guard original.isNull else { return }
        busy = true; defer { busy = false }
        do { let account = try await session.call("i"); lists = Record.list(try await session.call("users/lists/list")); try Task.checkCancellation(); original = account; configs = account["notificationRecieveConfig"].object; emailTypes = Set(account["emailNotificationTypes"].array.compactMap(\.string)); error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func save() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard configs.values.allSatisfy({ $0["type"].string != "list" || !($0["userListId"].string ?? "").isEmpty }) else { throw APIError(code: "LIST_REQUIRED", message: "请为指定列表通知选择一个列表。") }
            let fresh = try await session.call("i")
            let changedTypes = configs.filter { original["notificationRecieveConfig"][$0.key] != $0.value }
            guard changedTypes.allSatisfy({ fresh["notificationRecieveConfig"][$0.key] == original["notificationRecieveConfig"][$0.key] }) else { throw APIError(code: "CONFLICT", message: "通知偏好已在其他设备改变，请重新进入核对。") }
            var fields: [String: JSONValue] = [:]
            if !changedTypes.isEmpty { var merged = fresh["notificationRecieveConfig"].object; merged.merge(changedTypes) { _, new in new }; fields["notificationRecieveConfig"] = .object(merged) }
            if emailTypes != Set(original["emailNotificationTypes"].array.compactMap(\.string)) {
                guard fresh["emailNotificationTypes"] == original["emailNotificationTypes"] else { throw APIError(code: "CONFLICT", message: "邮件偏好已改变，请重新进入核对。") }
                fields["emailNotificationTypes"] = .strings(emailTypes.sorted())
            }
            guard !fields.isEmpty else { error = "没有需要保存的修改"; return }
            do { _ = try await session.call("i/update", fields, mutation: true) } catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            let confirmed = try await session.call("i"); guard fields.allSatisfy({ confirmed[$0.key] == $0.value }) else { throw APIError.uncertain }; original = confirmed; error = "已保存通知偏好"
        } catch { self.error = error.localizedDescription }
    }
}

struct OlderNotesPrivacyView: View {
    @Environment(AppSession.self) private var session
    @State private var original: JSONValue = .null
    @State private var followers: JSONValue = .null
    @State private var hidden: JSONValue = .null
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Text("按服务器的时间规则限制旧帖可见性；不删除帖子。已联邦分发的副本不保证从外站消失。").font(.footnote)
            Section("较早帖子仅关注者可见") { OlderNotesThreshold(value: $followers) }.disabled(original.isNull || busy)
            Section("较早帖子隐藏") { OlderNotesThreshold(value: $hidden) }.disabled(original.isNull || busy)
            Button("保存旧帖可见性") { Task { await save() } }.disabled(original.isNull || busy)
            if let error { Text(error) }
        }.puboForm().navigationTitle("旧帖可见性").task { guard original.isNull else { return }; do { original = try await session.call("i"); followers = original["makeNotesFollowersOnlyBefore"]; hidden = original["makeNotesHiddenBefore"] } catch { self.error = error.localizedDescription } }
    }
    private func save() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let changed = ["makeNotesFollowersOnlyBefore": followers, "makeNotesHiddenBefore": hidden].filter { original[$0.key] != $0.value }
            guard !changed.isEmpty else { error = "没有需要保存的修改"; return }
            let fresh = try await session.call("i"); guard changed.allSatisfy({ fresh[$0.key] == original[$0.key] }) else { throw APIError(code: "CONFLICT", message: "设置已改变，请重新进入核对。") }
            do { _ = try await session.call("i/update", changed, mutation: true) } catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            let checked = try await session.call("i"); guard changed.allSatisfy({ checked[$0.key] == $0.value }) else { throw APIError.uncertain }; original = checked; error = "已保存旧帖可见性"
        } catch { self.error = error.localizedDescription }
    }
}

private struct OlderNotesThreshold: View {
    @Binding var value: JSONValue
    private var mode: String { value.isNull ? "none" : value.int < 0 ? "relative" : "absolute" }
    var body: some View {
        Picker("限制方式", selection: Binding(get: { mode }, set: { value = $0 == "none" ? .null : $0 == "relative" ? .number(-604800) : .number(floor(Date().timeIntervalSince1970)) })) { Text("不限制").tag("none"); Text("经过一段时间").tag("relative"); Text("指定日期之前").tag("absolute") }
        if mode == "relative" { TextField("经过的小时数", value: Binding(get: { max(1, abs(value.int) / 3600) }, set: { value = .number(-Double(max(1, min(876000, $0))) * 3600) }), format: .number).keyboardType(.numberPad) }
        if mode == "absolute" { DatePicker("日期", selection: Binding(get: { Date(timeIntervalSince1970: Double(value.int)) }, set: { value = .number(floor($0.timeIntervalSince1970)) }), displayedComponents: .date) }
    }
}
