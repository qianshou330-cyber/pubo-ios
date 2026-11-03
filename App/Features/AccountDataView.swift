import SwiftUI
import PUBOCore

struct AccountDataView: View {
    @Environment(AppSession.self) private var session
    @State private var exportKind = "notes"
    @State private var importKind = "following"
    @State private var excludeMuting = false
    @State private var excludeInactive = false
    @State private var withReplies = false
    @State private var file: Record?
    @State private var picker = false
    @State private var aliases = ""
    @State private var originalAliases: JSONValue = .null
    @State private var destination = ""
    @State private var moveAcknowledged = false
    @State private var operation: String?
    @State private var busy = false
    @State private var locked = false
    @State private var error: String?
    private let exports = [("notes", "帖子"), ("following", "关注"), ("mute", "静音"), ("blocking", "屏蔽"), ("user-lists", "列表"), ("antennas", "天线"), ("favorites", "收藏"), ("clips", "剪藏")]
    private let imports = [("following", "关注"), ("muting", "静音"), ("blocking", "屏蔽"), ("user-lists", "列表"), ("antennas", "天线")]
    var body: some View {
        Form {
            Section("导出") {
                Picker("内容", selection: $exportKind) { ForEach(exports, id: \.0) { Text($0.1).tag($0.0) } }
                if exportKind == "following" { Toggle("排除静音用户", isOn: $excludeMuting); Toggle("排除不活跃用户", isOn: $excludeInactive) }
                Button("创建导出任务") { operation = "export" }.disabled(locked)
                Text("任务由服务器异步处理，完成后文件进入网盘。接口受理不代表文件已生成。").font(.footnote)
                NavigationLink("查看网盘文件") { DriveManagerView() }
            }
            Section("导入") {
                Picker("内容", selection: $importKind) { ForEach(imports, id: \.0) { Text($0.1).tag($0.0) } }
                Button(file?["name"].string ?? "从网盘选择导入文件") { picker = true }
                if importKind == "following" { Toggle("同时接收被关注者的回复", isOn: $withReplies) }
                Text("使用对应的 Misskey 导出文件；导入会批量修改账号数据，请先备份。").font(.footnote)
                Button("提交导入任务") { operation = "import" }.disabled(file == nil || locked)
            }
            if locked { Section { Text("上次任务已提交或结果未知，暂不重复创建。请到网盘或相应列表核对任务结果。"); Button("我已核对，允许创建下一项任务") { try? session.markPendingAction("account-data-job", pending: false); locked = false } } }
            Section("账号别名") {
                TextField("曾用账号的公开链接（每行一个，最多 10 个）", text: $aliases, axis: .vertical).textInputAutocapitalization(.never)
                Button("保存账号别名") { operation = "aliases" }
            }
            Section("迁移到其他账号") {
                Text("先在目标账号添加当前账号为别名。迁移会把关注者引导至目标，当前账号功能将受限制；帖子与媒体不会自动转移。服务器会验证目标及迁移资格。").font(.footnote)
                TextField("目标 @用户名@服务器", text: $destination).textInputAutocapitalization(.never)
                Toggle("我已备份数据并理解迁移影响", isOn: $moveAcknowledged)
                Button("申请账号迁移", role: .destructive) { operation = "move" }.disabled(!moveAcknowledged || destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error { ErrorBanner(message: error) }
        }.disabled(busy).puboForm().navigationTitle("数据与账号迁移").task { locked = session.hasPendingAction("account-data-job"); do { originalAliases = try await session.call("i")["alsoKnownAs"]; aliases = originalAliases.array.compactMap(\.string).joined(separator: "\n") } catch { self.error = error.localizedDescription } }
            .sheet(isPresented: $picker) { DrivePicker { file = $0 } }
            .alert(operation == "move" ? "确认迁移到 \(destination)？此操作影响关注者与当前账号使用。" : operation == "import" ? "确认批量导入所选文件？" : operation == "aliases" ? "确认更新公开账号别名？" : "确认创建导出任务？", isPresented: Binding(get: { operation != nil }, set: { if !$0 { operation = nil } }), presenting: operation) { selected in
                Button("确认", role: selected == "move" || selected == "import" ? .destructive : nil) { Task { await perform(selected) } }
                Button("取消", role: .cancel) { operation = nil }
            }
    }
    private func perform(_ selected: String) async {
        guard !busy else { return }; busy = true; defer { busy = false; operation = nil }
        do {
            if selected == "aliases" {
                let list = aliases.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }; guard list.count <= 10, Set(list).count == list.count, list.allSatisfy({ safeMediaURL($0) != nil }) else { throw APIError(code: "INVALID_ALIASES", message: "请填写不重复的 HTTPS 账号链接，最多 10 个。") }
                let current = try await session.call("i"); guard current["alsoKnownAs"] == originalAliases else { throw APIError(code: "CONFLICT", message: "别名已改变，请重新进入核对。") }
                let desired = JSONValue.strings(list)
                do { _ = try await session.call("i/update", ["alsoKnownAs": desired], mutation: true) } catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
                let result = try await session.call("i"); guard result["alsoKnownAs"] == desired else { throw APIError.uncertain }; originalAliases = desired; error = "别名已更新"; return
            }
            if selected == "move" {
                let current = try await session.call("i"); guard current["movedTo"].isNull && current["movedToUri"].isNull else { throw APIError(code: "ALREADY_MOVED", message: "此账号已经迁移，请刷新个人主页。") }
                _ = try await session.security.call(session: session, path: "i/move", fields: ["moveToAccount": .string(destination.trimmingCharacters(in: .whitespacesAndNewlines))], mutation: true)
                try await session.refreshUser(); error = "迁移请求已受理，请核对个人主页和目标账号。"; return
            }
            guard !locked else { return }; try session.markPendingAction("account-data-job", pending: true); locked = true
            var fields: [String: JSONValue] = [:]
            if selected == "export", exportKind == "following" { fields = ["excludeMuting": .bool(excludeMuting), "excludeInactive": .bool(excludeInactive)] }
            if selected == "import" { guard let file else { throw APIError.invalidResponse }; fields["fileId"] = .string(file.id); if importKind == "following" { fields["withReplies"] = .bool(withReplies) } }
            _ = try await session.security.call(session: session, path: "i/" + selected + "-" + (selected == "export" ? exportKind : importKind), fields: fields, mutation: true)
            error = "服务器已受理任务，请稍后核对结果。"
        } catch { self.error = error.localizedDescription + (selected == "move" ? " 请先核对个人主页的迁移状态，不要重复提交。" : "") }
    }
}
