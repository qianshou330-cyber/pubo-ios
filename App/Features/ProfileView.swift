import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
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
                    if let url = safeMediaURL(user["bannerUrl"].string) { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { PUBOTheme.button }.frame(height: 150).clipped().accessibilityLabel("个人主页背景图") }
                    HStack { Avatar(user: user, size: 64); VStack(alignment: .leading) { Text(user.displayName).font(.title2.bold()); Text("@" + (user["username"].string ?? "")).foregroundStyle(.secondary) } }
                    RoleBadges(user: user)
                    if let description = user["description"].string { NoteText(text: description) }
                    ForEach(Array(user["fields"].array.enumerated()), id: \.offset) { _, field in VStack(alignment: .leading) { Text(field["name"].string ?? "").font(.caption.bold()); NoteText(text: field["value"].string ?? "") } }
                    HStack {
                        NavigationLink("关注 \(user["followingCount"].int)") { FollowListView(userID: userID, followers: false) }
                        Spacer()
                        NavigationLink("关注者 \(user["followersCount"].int)") { FollowListView(userID: userID, followers: true) }
                    }.font(.callout)
                    if own { Button("编辑个人资料") { editing = true } }
                    else if session.user != nil {
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
            if let user, !user["pinnedNotes"].array.isEmpty { Section("置顶帖子") { ForEach(Record.list(user["pinnedNotes"])) { NoteCard(note: $0) } } }
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
    @State private var selectingMedia = false
    @State private var mediaTarget = "avatarId"
    @State private var avatar: Record?
    @State private var banner: Record?
    @State private var photo: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var profileFields: [ProfileField] = []
    @State private var restoredProfile = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("昵称", text: $name)
                TextEditor(text: $description).scrollContentBackground(.hidden).frame(minHeight: 160)
                mediaRow("头像", field: "avatarId", file: avatar)
                mediaRow("背景图", field: "bannerId", file: banner)
                Section("附加资料") {
                    ForEach($profileFields) { $field in
                        VStack { TextField("名称", text: $field.name); TextField("内容", text: $field.value, axis: .vertical); Button("移除此项", role: .destructive) { profileFields.removeAll { $0.id == field.id } } }
                    }
                    if profileFields.count < 16 { Button("添加附加资料") { profileFields.append(ProfileField()) } }
                }
                NavigationLink("头像装饰") { AvatarDecorationsView() }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy)
                .puboForm().navigationTitle("编辑资料").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy) }
                }.task { guard !restoredProfile else { return }; restoredProfile = true; name = session.user?["name"].string ?? ""; description = session.user?["description"].string ?? ""; profileFields = (session.user?["fields"].array ?? []).map { ProfileField(name: $0["name"].string ?? "", value: $0["value"].string ?? "") } }
                .sheet(isPresented: $selectingMedia) { DrivePicker(imagesOnly: true) { selected in setMedia(selected) } }
                .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
                .onChange(of: photo) { _, item in Task { await upload(item) } }
        }
    }
    private func mediaRow(_ title: String, field: String, file: Record?) -> some View {
        VStack(alignment: .leading) {
            Menu(title) {
                Button("从相册上传") { mediaTarget = field; showPhotos = true }
                Button("从网盘选择") { mediaTarget = field; selectingMedia = true }
            }.frame(minHeight: 44)
            if let file { Text(file["name"].string ?? "已选择图片").font(.caption) }
        }
    }
    private func setMedia(_ file: Record) {
        guard file["type"].string?.hasPrefix("image/") == true, !file["isSensitive"].bool else { error = "请选择非敏感的图片文件。"; return }
        if mediaTarget == "avatarId" { avatar = file } else { banner = file }
    }
    private func upload(_ item: PhotosPickerItem?) async {
        guard !busy, let item else { return }; busy = true; defer { busy = false; photo = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first ?? .image
            let file = try await session.upload(data: data, name: "PUBO-profile-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "jpg")", mime: type.preferredMIMEType ?? "image/jpeg")
            setMedia(file)
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        var fields: [String: JSONValue] = ["name": .string(name), "description": .string(description)]
        fields["fields"] = .array(profileFields.map { .object(["name": .string($0.name), "value": .string($0.value)]) })
        if let avatar { fields["avatarId"] = .string(avatar.id) }; if let banner { fields["bannerId"] = .string(banner.id) }
        do { _ = try await session.call("i/update", fields, mutation: true); try await session.refreshUser(); onSaved(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct ProfileField: Identifiable { let id = UUID(); var name = ""; var value = "" }

struct ReportView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let userID: String
    var context = ""
    @State private var comment = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form { Text("请描述需要管理员核查的问题，并提供相关帖子链接。"); TextEditor(text: $comment).scrollContentBackground(.hidden).frame(minHeight: 160); if let error { Text(error).foregroundStyle(.red) } }
                .puboForm().navigationTitle("举报用户").task { if comment.isEmpty { comment = context } }.toolbar {
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
    @State private var authorization = WebAuthorization()
    @State private var authorizing = false
    private var version: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—") + ")" }
    var body: some View {
        NavigationStack {
            Form {
                if let user = session.user { Section { NavigationLink { ProfileView(userID: user.id) } label: { HStack { Avatar(user: user, size: 56); Text(user.displayName).font(.title2.bold()) } } }.listRowBackground(PUBOTheme.panel) }
                Section { NavigationLink("搜索") { SearchView() }; NavigationLink("我的收藏") { FavoritesView() }; NavigationLink("定时帖子") { ScheduledNotesView() } }.listRowBackground(PUBOTheme.panel)
                Section("私信隐私") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("谁可以发起聊天").font(.subheadline)
                        Picker("谁可以发起聊天", selection: $chatScope) {
                            Text("所有人").tag("everyone"); Text("关注我的人").tag("followers"); Text("我关注的人").tag("following"); Text("仅相互关注").tag("mutual"); Text("不允许").tag("none")
                        }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("仅相互关注：未互相关注的人可发送一条文字留言，回复后可继续聊天。").font(.footnote).foregroundStyle(.secondary)
                    Button("保存接收设置") { Task { do { _ = try await session.call("i/update", ["chatScope": .string(chatScope)], mutation: true); try await session.refreshUser(); error = "设置已保存" } catch { self.error = error.localizedDescription } } }
                }
                .listRowBackground(PUBOTheme.panel)
                Section("账号") {
                    NavigationLink("锁屏推送") { NativePushSettingsView() }
                    if session.authorizationRequired { Text("需要补充授权以使用新增功能。取消授权不会删除草稿。").font(.footnote) }
                    Button(authorizing ? "正在授权…" : "重新授权（保留草稿）") { Task { authorizing = true; defer { authorizing = false }; do { let token = try await authorization.login(api: session.api); try await session.install(token: token); error = "授权已更新，请手动重试原操作。" } catch { self.error = error.localizedDescription } } }.disabled(authorizing)
                    Link("找回密码", destination: Endpoint.origin.appendingPathComponent("reset-password"))
                    Link("更多安全设置", destination: Endpoint.origin.appendingPathComponent("settings/security"))
                    NavigationLink("删除账号") { DeleteAccountView() }
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                }
                .listRowBackground(PUBOTheme.panel)
                Section("关于") {
                    Text("PUBO iPhone · " + version)
                    Text(session.meta["nativePushAvailable"].bool ? "锁屏推送可在账号设置中开启。" : "通知在 App 内更新，当前锁屏推送通道尚未开放。").font(.footnote)
                    Link("隐私政策", destination: Endpoint.origin.appendingPathComponent("privacy.html"))
                    Link("支持与反馈", destination: URL(string: "mailto:qianshou330@gmail.com")!)
                    if let url = safeMediaURL(session.meta["tosUrl"].string) { Link("服务条款", destination: url) }
                    Link("公开源码", destination: URL(string: "https://github.com/qianshou330-cyber/pubo-ios")!)
                }
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

