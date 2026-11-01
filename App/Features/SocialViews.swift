import SwiftUI
import PUBOCore

struct SearchView: View {
    @Environment(AppSession.self) private var session
    @State private var query = ""
    @State private var category = "notes"
    @State private var records: [Record] = []
    @State private var tags: [String] = []
    @State private var error: String?
    @State private var busy = false
    @State private var more = false
    @State private var offset = 0
    @State private var searchID = UUID()
    @State private var searched = false
    var body: some View {
        List {
            Picker("搜索类型", selection: $category) { Text("帖子").tag("notes"); Text("用户").tag("users"); Text("话题").tag("tags") }.pickerStyle(.segmented)
            if let error { ErrorBanner(message: error) { Task { await search(reset: true) } } }
            if category == "notes" { ForEach(records) { NoteCard(note: $0) } }
            if category == "users" {
                ForEach(records) { user in
                    NavigationLink { ProfileView(userID: user.id) } label: {
                        HStack { Avatar(user: user); VStack(alignment: .leading) { Text(user.displayName); Text("@" + (user["username"].string ?? "")).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
            }
            if category == "tags" { ForEach(tags, id: \.self) { tag in NavigationLink("#" + tag) { TagNotesView(tag: tag) } } }
            if busy { ProgressView() }
            else if more { Button("加载更多") { Task { await search(reset: false) } } }
            else if searched && records.isEmpty && tags.isEmpty && error == nil { Text("没有找到相关内容").foregroundStyle(.secondary) }
        }.puboList().navigationTitle("搜索").searchable(text: $query, prompt: "搜索帖子、用户或话题")
            .onSubmit(of: .search) { Task { await search(reset: true) } }
            .onChange(of: category) { _, _ in Task { await search(reset: true) } }
            .onChange(of: query) { _, _ in searchID = UUID(); busy = false; searched = false; records = []; tags = []; offset = 0; more = false; error = nil }
            .onDisappear { searchID = UUID() }
    }
    private func search(reset: Bool) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, reset || !busy else { return }
        let attempt = UUID(); searchID = attempt; busy = true
        let kind = category
        if reset { records = []; tags = []; offset = 0; more = false }
        defer { if searchID == attempt { busy = false } }
        var fields: [String: JSONValue] = ["query": .string(kind == "tags" ? text.trimmingCharacters(in: CharacterSet(charactersIn: "#")) : text), "limit": .number(30)]
        if kind == "notes", !reset, let id = records.last?.id { fields["untilId"] = .string(id) }
        if kind != "notes" { fields["offset"] = .number(Double(offset)) }
        do {
            let result = try await session.call(kind == "tags" ? "hashtags/search" : kind + "/search", fields)
            guard searchID == attempt, kind == category else { return }
            if kind == "tags" { for tag in result.array.compactMap(\.string) where !tags.contains(tag) { tags.append(tag) } }
            else if kind == "users" { for user in Record.list(result) where !records.contains(where: { $0.id == user.id }) { records.append(user) } }
            else { records = Records.merge(records, Record.list(result), limit: 10_000) }
            offset += result.array.count; more = result.array.count == 30; searched = true; error = nil
        } catch { if searchID == attempt { self.error = error.localizedDescription } }
    }
}

struct TagNotesView: View {
    @Environment(AppSession.self) private var session
    let tag: String
    @State private var notes: [Record] = []
    @State private var error: String?
    @State private var more = true
    @State private var busy = false
    var body: some View {
        List { ForEach(notes) { NoteCard(note: $0) }; if let error { ErrorBanner(message: error) { Task { await load() } } }; if more { Button("加载更多") { Task { await load() } }.disabled(busy) } }
            .puboList().navigationTitle("#" + tag).task { await load() }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var fields: [String: JSONValue] = ["tag": .string(tag), "limit": .number(30)]
        if let id = notes.last?.id { fields["untilId"] = .string(id) }
        do { let result = Record.list(try await session.call("notes/search-by-tag", fields)); notes = Records.merge(notes, result, limit: 10_000); more = result.count == 30; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct FavoritesView: View {
    @Environment(AppSession.self) private var session
    @State private var rows: [Record] = []
    @State private var error: String?
    @State private var more = true
    @State private var busy = false
    var body: some View {
        List {
            ForEach(rows) { row in if !row["note"].isNull { NoteCard(note: Record(row["note"])) } }
            if let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }
            if busy { ProgressView() } else if more { Button("加载更多") { Task { await load() } } }
            if !busy && rows.isEmpty && error == nil { Text("还没有收藏帖子") }
        }.puboList().navigationTitle("我的收藏").task { await load(reset: true) }.refreshable { await load(reset: true) }
    }
    private func load(reset: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var fields: [String: JSONValue] = ["limit": .number(30)]
        if !reset, let id = rows.last?.id { fields["untilId"] = .string(id) }
        do { let result = Record.list(try await session.call("i/favorites", fields)); rows = reset ? result : Records.merge(rows, result, limit: 10_000); more = result.count == 30; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct PollView: View {
    @Environment(AppSession.self) private var session
    let noteID: String
    let initial: JSONValue
    @State private var current: JSONValue?
    @State private var busy = false
    @State private var uncertain = false
    @State private var error: String?
    private var poll: JSONValue { current ?? initial }
    private var choices: [JSONValue] { poll["choices"].array }
    private var total: Int { choices.reduce(0) { $0 + $1["votes"].int } }
    private var expired: Bool { poll["expiresAt"].string.flatMap(SocialContent.date).map { $0 <= Date() } ?? false }
    private var voted: Bool { choices.contains { $0["isVoted"].bool } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                Button { Task { await vote(index) } } label: {
                    HStack { Image(systemName: choice["isVoted"].bool ? "checkmark.circle.fill" : "circle"); Text(choice["text"].string ?? ""); Spacer(); Text("\(choice["votes"].int)") }
                        .frame(minHeight: 44).padding(.horizontal, 10).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(busy || uncertain || expired || choice["isVoted"].bool || (voted && !poll["multiple"].bool)).accessibilityIdentifier("poll.choice.\(index)")
            }
            Text("\(total) 票 · " + (poll["multiple"].bool ? "可多选" : "单选") + (expired ? " · 已结束" : "")).font(.caption).foregroundStyle(.secondary)
            if let date = poll["expiresAt"].string.flatMap(SocialContent.date) { Text("结束时间：\(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Button(uncertain ? "核对投票结果" : "更新票数") { Task { await refresh() } }.font(.caption).disabled(busy)
        }
    }
    private func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { current = try await session.call("notes/show", ["noteId": .string(noteID)])["poll"]; uncertain = false; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func vote(_ index: Int) async {
        guard !busy, !uncertain, !expired else { return }; busy = true; defer { busy = false }
        do { _ = try await session.call("notes/polls/vote", ["noteId": .string(noteID), "choice": .number(Double(index))], mutation: true); uncertain = true; current = try await session.call("notes/show", ["noteId": .string(noteID)])["poll"]; uncertain = false; error = nil }
        catch { if (error as? APIError)?.code == "OUTCOME_UNKNOWN" { uncertain = true }; self.error = error.localizedDescription }
    }
}

struct PollEditor: View {
    @Binding var draft: PollDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("投票").font(.headline)
            ForEach(draft.choices.indices, id: \.self) { index in
                HStack { TextField("选项 \(index + 1)", text: $draft.choices[index]).textFieldStyle(.roundedBorder).accessibilityIdentifier("poll.option.\(index)"); if draft.choices.count > 2 { Button { draft.choices.remove(at: index) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel("删除选项 \(index + 1)") } }
            }
            if draft.choices.count < 10 { Button("添加选项") { draft.choices.append("") } }
            Toggle("允许多选", isOn: $draft.multiple)
            Toggle("设置结束时间", isOn: Binding(get: { draft.expiresAt != nil }, set: { draft.expiresAt = $0 ? Date().addingTimeInterval(86_400) : nil }))
            if draft.expiresAt != nil { DatePicker("结束时间", selection: Binding(get: { draft.expiresAt ?? Date() }, set: { draft.expiresAt = $0 }), in: Date()..., displayedComponents: [.date, .hourAndMinute]) }
        }.font(.subheadline).padding(12).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 8))
    }
}
