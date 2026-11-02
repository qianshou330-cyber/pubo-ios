import SwiftUI
import PUBOCore

struct AvatarDecorationsView: View {
    @Environment(AppSession.self) private var session
    @State private var available: [Record] = []
    @State private var selected: [JSONValue] = []
    @State private var error: String?
    @State private var busy = false
    private var limit: Int { min(16, max(0, session.user?["policies"]["avatarDecorationLimit"].int ?? 0)) }
    private var preview: Record? { guard let user = session.user else { return nil }; var value = user.raw.object; value["avatarDecorations"] = .array(selected); return Record(.object(value)) }
    var body: some View {
        List {
            if let preview { Avatar(user: preview, size: 96).frame(maxWidth: .infinity, minHeight: 140) }
            Section("已选装饰 \(selected.count)/\(limit)") {
                ForEach(Array(selected.enumerated()), id: \.offset) { index, value in
                    VStack(alignment: .leading) {
                        Text(available.first(where: { $0.id == value["id"].string })?["name"].string ?? "装饰")
                        Slider(value: numeric(index, "angle"), in: -0.5...0.5) { Text("旋转") }
                        Slider(value: numeric(index, "offsetX"), in: -0.25...0.25) { Text("水平位置") }
                        Slider(value: numeric(index, "offsetY"), in: -0.25...0.25) { Text("垂直位置") }
                        Toggle("水平翻转", isOn: Binding(get: { selected.indices.contains(index) && selected[index]["flipH"].bool }, set: { update(index, "flipH", .bool($0)) }))
                        Button("移除", role: .destructive) { selected.remove(at: index) }
                    }
                }
            }
            Section("可用装饰") {
                ForEach(available) { item in
                    Button { var value = item.raw.object; value["angle"] = .number(0); selected.append(.object(value)) } label: {
                        HStack { if let url = safeMediaURL(item["url"].string) { AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(width: 40, height: 40) }; Text(item["name"].string ?? "装饰") }
                    }.disabled(selected.count >= limit || !allowed(item))
                }
            }
            if let error { ErrorBanner(message: error) }
            Button("保存头像装饰") { Task { await save() } }.disabled(busy)
        }.puboList().navigationTitle("头像装饰").disabled(busy).task {
            selected = session.user?["avatarDecorations"].array ?? []
            do { available = Record.list(try await session.call("get-avatar-decorations")) } catch { self.error = error.localizedDescription }
        }
    }
    private func allowed(_ item: Record) -> Bool {
        let roles = Set(session.user?["roles"].array.compactMap { $0["id"].string } ?? [])
        let required = Set(item["roleIdsThatCanBeUsedThisDecoration"].array.compactMap(\.string))
        return required.isEmpty || !required.isDisjoint(with: roles)
    }
    private func numeric(_ index: Int, _ key: String) -> Binding<Double> {
        Binding(get: { guard selected.indices.contains(index), case .number(let value) = selected[index][key] else { return 0 }; return value }, set: { update(index, key, .number($0)) })
    }
    private func update(_ index: Int, _ key: String, _ value: JSONValue) { guard selected.indices.contains(index) else { return }; var item = selected[index].object; item[key] = value; selected[index] = .object(item) }
    private func save() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let fields = selected.map { item in JSONValue.object(item.object.filter { ["id", "angle", "flipH", "offsetX", "offsetY"].contains($0.key) }) }
        do {
            do { _ = try await session.call("i/update", ["avatarDecorations": .array(fields)], mutation: true) }
            catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            try await session.refreshUser()
            let actual = session.user?["avatarDecorations"].array ?? []
            guard actual.count == fields.count, zip(actual, fields).allSatisfy({ pair in pair.1.object.allSatisfy { pair.0[$0.key] == $0.value } }) else { throw APIError.uncertain }
            error = "头像装饰已保存"
        } catch { self.error = error.localizedDescription }
    }
}
