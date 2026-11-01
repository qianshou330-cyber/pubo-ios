import SwiftUI
import PUBOCore

struct DrivePicker: View {
    @Environment(\.dismiss) private var dismiss
    var imagesOnly = false
    let choose: (Record) -> Void
    var body: some View {
        NavigationStack {
            DriveFolderView(imagesOnly: imagesOnly) { file in choose(file); dismiss() }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

private struct DriveFolderView: View {
    @Environment(AppSession.self) private var session
    var folderID: String? = nil
    var title = "我的网盘"
    let imagesOnly: Bool
    let choose: (Record) -> Void
    @State private var folders: [Record] = []
    @State private var files: [Record] = []
    @State private var foldersMore = true
    @State private var filesMore = true
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            Section("文件夹") {
                ForEach(folders) { folder in NavigationLink { DriveFolderView(folderID: folder.id, title: folder["name"].string ?? "文件夹", imagesOnly: imagesOnly, choose: choose) } label: { Label(folder["name"].string ?? "文件夹", systemImage: "folder") } }
                if foldersMore && loaded { Button("更多文件夹") { Task { await load(foldersOnly: true) } }.disabled(busy) }
            }
            Section("文件") {
                ForEach(files) { file in
                    Button { choose(file) } label: {
                        HStack { Image(systemName: file["type"].string?.hasPrefix("image/") == true ? "photo" : "doc"); VStack(alignment: .leading) { Text(file["name"].string ?? "文件").lineLimit(2); Text(file["isSensitive"].bool ? "敏感媒体，不在 App 预览" : ByteCountFormatter.string(fromByteCount: Int64(file["size"].int), countStyle: .file)).font(.caption).foregroundStyle(.secondary) } }.frame(minHeight: 44)
                    }.buttonStyle(.plain).disabled(imagesOnly && file["isSensitive"].bool)
                }
                if filesMore && loaded { Button("更多文件") { Task { await load(filesOnly: true) } }.disabled(busy) }
                if loaded && files.isEmpty { Text("这个文件夹没有可选文件").foregroundStyle(.secondary) }
            }
            if busy { ProgressView() }
        }.puboList().navigationTitle(title).task { if !loaded { await load() } }
    }
    private func load(foldersOnly: Bool = false, filesOnly: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let root: [String: JSONValue] = ["folderId": folderID.map(JSONValue.string) ?? .null, "limit": .number(30)]
            if !filesOnly && foldersMore {
                var fields = root
                if let id = folders.last?.id { fields["untilId"] = .string(id) }
                let result = Record.list(try await session.call("drive/folders", fields))
                folders = Records.merge(folders, result, limit: 10_000); foldersMore = result.count == 30
            }
            if !foldersOnly && filesMore {
                var fields = root
                if imagesOnly { fields["type"] = .string("image/*") }
                if let id = files.last?.id { fields["untilId"] = .string(id) }
                let result = Record.list(try await session.call("drive/files", fields))
                files = Records.merge(files, result, limit: 10_000); filesMore = result.count == 30
            }
            loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
