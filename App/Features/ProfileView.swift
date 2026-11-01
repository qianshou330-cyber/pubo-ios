import SwiftUI
import PUBOCore

struct ProfileView: View {
    @Environment(AppSession.self) private var session
    let userID: String
    @State private var user: Record?
    @State private var notes: [Record] = []
    @State private var error: String?
    @State private var reporting = false
    @State private var editing = false
    @State private var busy = false
    @State private var hasMore = true
    private var own: Bool { session.user?.id == userID }
    var body: some View {
        List {
            if let user {
                Section {
                    HStack { Avatar(user: user, size: 64); VStack(alignment: .leading) { Text(user.displayName).font(.title2.bold()); Text("@" + (user["username"].string ?? "")).foregroundStyle(.secondary) } }
                    if let description = user["description"].string { Text(description).textSelection(.enabled) }
                    HStack {
                        NavigationLink("关注 \(user["followingCount"].int)") { FollowListView(userID: userID, followers: false) }
                        Spacer()
                        NavigationLink("关注者 \(user["followersCount"].int)") { FollowListView(userID: userID, followers: true) }
                    }.font(.callout)
                    if own { Button("编辑个人资料") { editing = true } }
                    else {
                        Button(user["isFollowing"].bool ? "取消关注" : "关注") { Task { await follow(user) } }.disabled(busy)
                        if user["host"].isNull { NavigationLink("发送私信") { ChatView(peer: user) } }
                        Menu("更多操作") {
                            Button("举报") { reporting = true }
                            Button(user["isBlocking"].bool ? "解除屏蔽" : "屏蔽此用户", role: .destructive) { Task { await block(user) } }
                        }
                    }
                }
            }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            Section("帖子") { ForEach(notes) { NoteCard(note: $0) }; if hasMore && !notes.isEmpty { Button("加载更多") { Task { await loadNotes(older: true) } }.disabled(busy) } }
        }.puboForm().navigationTitle(own ? "我的主页" : "个人主页").task { await load() }.refreshable { await load() }
            .sheet(isPresented: $reporting) { ReportView(userID: userID) }
            .sheet(isPresented: $editing) { EditProfileView { Task { await load() } } }
    }
    private func load() async {
        do { user = Record(try await session.call("users/show", ["userId": .string(userID)])); error = nil; await loadNotes() }
        catch { self.error = error.localizedDescription }
    }
    private func loadNotes(older: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["userId": .string(userID), "limit": .number(20)]
            if older, let id = notes.last?.id { fields["untilId"] = .string(id) }
            let result = Record.list(try await session.call("users/notes", fields))
            notes = older ? Records.merge(notes, result) : result; hasMore = result.count == 20
        } catch { self.error = error.localizedDescription }
    }
    private func follow(_ user: Record) async {
        busy = true; defer { busy = false }
        do { _ = try await session.call(user["isFollowing"].bool ? "following/delete" : "following/create", ["userId": .string(userID)], mutation: true); self.user = Record(try await session.call("users/show", ["userId": .string(userID)])) }
        catch { self.error = error.localizedDescription }
    }
    private func block(_ user: Record) async {
        do { _ = try await session.call(user["isBlocking"].bool ? "blocking/delete" : "blocking/create", ["userId": .string(userID)], mutation: true); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct FollowListView: View {
    @Environment(AppSession.self) private var session
    let userID: String
    let followers: Bool
    @State private var rows: [JSONValue] = []
    @State private var error: String?
    @State private var hasMore = true
    var body: some View {
        List {
            ForEach(rows, id: \.selfID) { row in
                let user = Record(row[followers ? "follower" : "followee"])
                NavigationLink { ProfileView(userID: user.id) } label: { HStack { Avatar(user: user); Text(user.displayName) } }
            }
            if let error { ErrorBanner(message: error) }
            if hasMore { Button("加载更多") { Task { await load() } } }
        }.puboForm().navigationTitle(followers ? "关注者" : "关注").task { await load() }
    }
    private func load() async {
        do {
            var fields: [String: JSONValue] = ["userId": .string(userID), "limit": .number(30)]
            if let id = rows.last?["id"].string { fields["untilId"] = .string(id) }
            let result = try await session.call(followers ? "users/followers" : "users/following", fields)
            rows += result.array.filter { incoming in !rows.contains { $0["id"] == incoming["id"] } }; hasMore = result.array.count == 30
        } catch { self.error = error.localizedDescription }
    }
}

struct EditProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var name = ""
    @State private var description = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form { TextField("昵称", text: $name); TextEditor(text: $description).scrollContentBackground(.hidden).frame(minHeight: 160); if let error { Text(error).foregroundStyle(.red) } }
                .puboForm().navigationTitle("编辑资料").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy) }
                }.task { name = session.user?["name"].string ?? ""; description = session.user?["description"].string ?? "" }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do { _ = try await session.call("i/update", ["name": .string(name), "description": .string(description)], mutation: true); try await session.refreshUser(); onSaved(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct ReportView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let userID: String
    @State private var comment = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form { Text("请描述需要管理员核查的问题，并提供相关帖子链接。"); TextEditor(text: $comment).scrollContentBackground(.hidden).frame(minHeight: 160); if let error { Text(error).foregroundStyle(.red) } }
                .puboForm().navigationTitle("举报用户").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("提交") { Task { busy = true; defer { busy = false }; do { _ = try await session.call("users/report-abuse", ["userId": .string(userID), "comment": .string(comment)], mutation: true); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(busy || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}

struct MyAccountView: View {
    @Environment(AppSession.self) private var session
    @State private var error: String?
    @State private var chatScope = "mutual"
    @State private var confirmLogout = false
    var body: some View {
        NavigationStack {
            Form {
                if let user = session.user { Section { NavigationLink { ProfileView(userID: user.id) } label: { HStack { Avatar(user: user, size: 56); Text(user.displayName).font(.title2.bold()) } } } }
                Section("私信隐私") {
                    Picker("谁可以发起聊天", selection: $chatScope) {
                        Text("所有人").tag("everyone"); Text("关注我的人").tag("followers"); Text("我关注的人").tag("following"); Text("仅相互关注").tag("mutual"); Text("不允许").tag("none")
                    }
                    Text("仅相互关注：未互相关注的人可发送一条文字留言，回复后可继续聊天。").font(.footnote).foregroundStyle(.secondary)
                    Button("保存接收设置") { Task { do { _ = try await session.call("i/update", ["chatScope": .string(chatScope)], mutation: true); try await session.refreshUser(); error = "设置已保存" } catch { self.error = error.localizedDescription } } }
                }
                .listRowBackground(PUBOTheme.panel)
                Section("账号") {
                    Link("更多安全设置", destination: Endpoint.origin.appendingPathComponent("settings/security"))
                    NavigationLink("删除账号") { DeleteAccountView() }
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                }
                .listRowBackground(PUBOTheme.panel)
                Section("关于") { Text("PUBO iPhone · 0.1.1"); Text("通知在 App 内更新，当前版本不提供锁屏推送。").font(.footnote); Link("公开源码", destination: URL(string: "https://github.com/qianshou330-cyber/pubo-ios")!) }
                .listRowBackground(PUBOTheme.panel)
                if let error { Text(error).foregroundStyle(.secondary) }
            }.puboForm().navigationTitle("我的").task { chatScope = session.user?["chatScope"].string ?? "mutual" }
                .confirmationDialog("退出后清除本机登录信息、草稿与聊天待发记录。", isPresented: $confirmLogout) { Button("退出登录", role: .destructive) { do { try session.logout() } catch { self.error = error.localizedDescription } } }
        }
    }
}

struct DeleteAccountView: View {
    @Environment(AppSession.self) private var session
    @State private var password = ""
    @State private var otp = ""
    @State private var confirmed = false
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Form {
            Text("删除账号会由服务器执行账号清理，无法通过本 App 撤销。请确认后继续。")
            SecureField("输入账号密码", text: $password).textContentType(.password)
            TextField("两步验证代码（如已启用）", text: $otp).textContentType(.oneTimeCode).keyboardType(.numberPad)
            Link("使用网页删除账号", destination: Endpoint.origin.appendingPathComponent("settings/other"))
            Button("申请永久删除账号", role: .destructive) { confirmed = true }.disabled(password.isEmpty || busy)
            if let error { Text(error).foregroundStyle(.red) }
        }.puboForm().navigationTitle("删除账号").confirmationDialog("确认删除你的 PUBO 账号？", isPresented: $confirmed) {
            Button("确认永久删除", role: .destructive) { Task { busy = true; defer { busy = false; password = ""; otp = "" }; do { var body: [String: JSONValue] = ["password": .string(password)]; if !otp.isEmpty { body["token"] = .string(otp) }; _ = try await session.call("i/delete-account", body, mutation: true); try session.logout() } catch { self.error = error.localizedDescription } } }
        }.onDisappear { password = ""; otp = "" }
    }
}
