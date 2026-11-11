import SwiftUI
import PUBOCore

struct DrivePicker: View {
    @Environment(\.dismiss) private var dismiss
    var imagesOnly = false
    var confirmedSensitiveChoice: ((Record) -> Void)? = nil
    let choose: (Record) -> Void
    var body: some View {
        NavigationStack {
            DriveFolderView(imagesOnly: imagesOnly) { file, confirmed in
                if confirmed, let confirmedSensitiveChoice { confirmedSensitiveChoice(file) } else { choose(file) }
                dismiss()
            }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

private struct DriveFolderView: View {
    @Environment(AppSession.self) private var session
    var folderID: String? = nil
    var title = "我的网盘"
    let imagesOnly: Bool
    let choose: (Record, Bool) -> Void
    @State private var folders: [Record] = []
    @State private var files: [Record] = []
    @State private var foldersMore = true
    @State private var filesMore = true
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false
    @State private var pendingSensitiveFile: Record?
    @State private var confirmSensitive = false
    @State private var selected = false
    @State private var selectionTask: Task<Void, Never>?
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            Section("文件夹") {
                ForEach(folders) { folder in NavigationLink { DriveFolderView(folderID: folder.id, title: folder["name"].string ?? "文件夹", imagesOnly: imagesOnly, choose: choose) } label: { Label(folder["name"].string ?? "文件夹", systemImage: "folder") } }
                if foldersMore && loaded { Button("更多文件夹") { Task { await load(foldersOnly: true) } }.disabled(busy) }
            }
            Section("文件") {
                ForEach(files) { file in
                    Button {
                        guard selectionTask == nil else { return }
                        selectionTask = Task { await requestSelection(file); selectionTask = nil }
                    } label: {
                        HStack { Image(systemName: file["type"].string?.hasPrefix("image/") == true ? "photo" : "doc"); VStack(alignment: .leading) { Text(file["name"].string ?? "文件").lineLimit(2); Text(file["isSensitive"].bool ? "敏感媒体，选择前需确认" : ByteCountFormatter.string(fromByteCount: Int64(max(0, file["size"].int)), countStyle: .file)).font(.caption).foregroundStyle(.secondary) } }.frame(minHeight: 44)
                    }.buttonStyle(.plain).disabled(busy || selected || !DriveMediaPolicy.canSelect(mime: file["type"].string ?? "", imagesOnly: imagesOnly)).accessibilityIdentifier("drive.select." + file.id)
                }
                if filesMore && loaded { Button("更多文件") { Task { await load(filesOnly: true) } }.disabled(busy) }
                if loaded && files.isEmpty { Text("这个文件夹没有可选文件").foregroundStyle(.secondary) }
            }
            if busy { ProgressView() }
        }.puboList().navigationTitle(title).task { if !loaded { await load() } }
            .alert("选择敏感文件？", isPresented: $confirmSensitive) {
                Button("取消", role: .cancel) { pendingSensitiveFile = nil }.accessibilityIdentifier("drive.select.cancel")
                Button("使用此文件") { if let file = pendingSensitiveFile { finishSelection(file, sensitiveConfirmed: true) }; pendingSensitiveFile = nil }.accessibilityIdentifier("drive.select.confirm")
            } message: { Text(imagesOnly ? "此图片可能包含敏感内容。若用于头像或背景图，其他人可能直接看到它。选择不会移除文件的敏感标记。" : "此文件可能包含敏感内容。选择不会移除敏感标记，也不会立即发送或发布。") }
            .onChange(of: session.generation) { _, _ in selectionTask?.cancel(); pendingSensitiveFile = nil; confirmSensitive = false; selected = true }
            .onDisappear { selectionTask?.cancel(); selectionTask = nil; pendingSensitiveFile = nil; confirmSensitive = false }
    }
    private func requestSelection(_ file: Record) async {
        guard !busy, !selected, DriveMediaPolicy.canSelect(mime: file["type"].string ?? "", imagesOnly: imagesOnly) else { return }
        busy = true; error = nil; defer { busy = false }
        let epoch = session.generation
        do {
            // A file may have been marked sensitive since the folder was listed.
            // Fresh metadata governs both disclosure and MIME eligibility.
            let value = try await session.call("drive/files/show", ["fileId": .string(file.id)])
            guard epoch == session.generation, !Task.isCancelled, !selected else { return }
            guard value["id"].string == file.id else { throw APIError.invalidResponse }
            let current = Record(value)
            guard DriveMediaPolicy.canSelect(mime: current["type"].string ?? "", imagesOnly: imagesOnly) else {
                throw APIError(code: "FILE_TYPE_CHANGED", message: "文件类型已变化，请重新选择图片。")
            }
            if let index = files.firstIndex(where: { $0.id == current.id }) { files[index] = current }
            if DriveMediaPolicy.requiresConfirmation(isSensitive: current["isSensitive"].bool) { pendingSensitiveFile = current; confirmSensitive = true }
            else { finishSelection(current) }
        } catch { if epoch == session.generation, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func finishSelection(_ file: Record, sensitiveConfirmed: Bool = false) {
        guard !selected else { return }; selected = true; choose(file, sensitiveConfirmed)
    }
    private func load(foldersOnly: Bool = false, filesOnly: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let root: [String: JSONValue] = ["folderId": folderID.map(JSONValue.string) ?? .null, "limit": .number(30)]
            if !filesOnly && foldersMore {
                var fields = root
                if let id = folders.last?.id { fields["untilId"] = .string(id) }
                let response = try await session.call("drive/folders", fields); try Task.checkCancellation()
                guard case .array = response else { throw APIError.invalidResponse }
                let result = Record.list(response)
                folders = Records.merge(folders, result, limit: 10_000); foldersMore = result.count == 30
            }
            if !foldersOnly && filesMore {
                var fields = root
                if imagesOnly { fields["type"] = .string("image/*") }
                if let id = files.last?.id { fields["untilId"] = .string(id) }
                let response = try await session.call("drive/files", fields); try Task.checkCancellation()
                guard case .array = response else { throw APIError.invalidResponse }
                let result = Record.list(response)
                files = Records.merge(files, result, limit: 10_000); filesMore = result.count == 30
            }
            loaded = true; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
