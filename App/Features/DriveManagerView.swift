import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PUBOCore

struct DriveManagerView: View {
    @Environment(AppSession.self) private var session
    var folderID: String? = nil
    var title = "网盘"
    @State private var folders: [Record] = []
    @State private var files: [Record] = []
    @State private var capacity: JSONValue = .null
    @State private var folderMore = true
    @State private var fileMore = true
    @State private var busy = false
    @State private var error: String?
    @State private var operation: DriveOperation?
    @State private var preview: Record?
    @State private var importer = false
    @State private var newFolder = false
    @State private var folderName = ""
    @State private var creationPending = false
    private var intentKey: String { "drive-create-folder-" + (folderID ?? "root") }
    var body: some View {
        List {
            if !capacity.isNull { Section("容量") { Text("已用 \(bytes(capacity["usage"])) / \(bytes(capacity["capacity"]))"); Text("网盘 \(bytes(capacity["driveUsage"])) · 私聊 \(bytes(capacity["chatUsage"])) · 预留 \(bytes(capacity["reservedUsage"]))").font(.caption) } }
            Section("文件夹") {
                ForEach(folders) { folder in
                    NavigationLink { DriveManagerView(folderID: folder.id, title: folder["name"].string ?? "文件夹") } label: { Label(folder["name"].string ?? "文件夹", systemImage: "folder") }
                        .contextMenu { Button("管理文件夹") { operation = DriveOperation(item: folder, folder: true) } }
                }
                if folderMore { Button("更多文件夹") { Task { await load(part: "folders") } }.disabled(busy) }
            }
            Section("文件") {
                ForEach(files) { file in
                    Button { operation = DriveOperation(item: file, folder: false) } label: { HStack { Image(systemName: file["type"].string?.hasPrefix("image/") == true ? "photo" : "doc"); VStack(alignment: .leading) { Text(file["name"].string ?? "文件").lineLimit(2); Text(bytes(file["size"])).font(.caption) } } }
                }
                if fileMore { Button("更多文件") { Task { await load(part: "files") } }.disabled(busy) }
            }
            if let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }
            if creationPending { Text("上次创建文件夹的结果待确认，请先核对当前列表。"); Button("已核对，允许继续创建") { do { try session.markPendingAction(intentKey, pending: false); creationPending = false } catch { self.error = error.localizedDescription } } }
            if busy { ProgressView() }
        }.puboList().navigationTitle(title)
            .toolbar { Menu { Button("上传文件") { importer = true }; Button("新建文件夹") { folderName = ""; newFolder = true }.disabled(creationPending) } label: { Image(systemName: "plus") }.disabled(busy).accessibilityLabel("网盘新增") }
            .task { creationPending = session.hasPendingAction(intentKey); await load(reset: true) }.refreshable { await load(reset: true) }
            .sheet(item: $operation) { operation in DriveItemManager(operation: operation) { Task { await load(reset: true) } } }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.item]) { result in Task { await upload(result) } }
            .alert("新建文件夹", isPresented: $newFolder) { TextField("文件夹名称", text: $folderName); Button("创建") { Task { await createFolder() } }.disabled(folderName.isEmpty || folderName.count > 200); Button("取消", role: .cancel) { } }
    }
    private func bytes(_ value: JSONValue) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, value.int)), countStyle: .file) }
    private func load(reset: Bool = false, part: String? = nil) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if reset { folders = []; files = []; folderMore = true; fileMore = true; capacity = try await session.call("drive") }
            for kind in ["folders", "files"] where part == nil || part == kind {
                if kind == "folders" ? !folderMore : !fileMore { continue }
                var fields: [String: JSONValue] = ["folderId": folderID.map(JSONValue.string) ?? .null, "limit": .number(30)]
                if let last = (kind == "folders" ? folders : files).last { fields["untilId"] = .string(last.id) }
                let response = try await session.call("drive/" + kind, fields); try Task.checkCancellation()
                guard case .array = response else { throw APIError.invalidResponse }
                if kind == "folders" { folders = Records.merge(folders, Record.list(response), limit: 10_000); folderMore = response.array.count == 30 }
                else { files = Records.merge(files, Record.list(response), limit: 10_000); fileMore = response.array.count == 30 }
            }
            error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func createFolder() async {
        guard !busy, !creationPending else { return }; busy = true
        do { try session.markPendingAction(intentKey, pending: true); creationPending = true; _ = try await session.call("drive/folders/create", ["name": .string(folderName), "parentId": folderID.map(JSONValue.string) ?? .null], mutation: true); try session.markPendingAction(intentKey, pending: false); creationPending = false; error = nil }
        catch { self.error = error.localizedDescription; busy = false; return }
        busy = false; await load(reset: true)
    }
    private func upload(_ result: Result<URL, Error>) async {
        guard !busy else { return }; busy = true
        do {
            let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "此文件超过 50 MiB。") }
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            let file = try await session.upload(data: Data(contentsOf: url), name: url.lastPathComponent, mime: type.preferredMIMEType ?? "application/octet-stream")
            if let folderID { _ = try await session.call("drive/files/update", ["fileId": .string(file.id), "folderId": .string(folderID)], mutation: true) }
            busy = false; await load(reset: true)
        } catch { busy = false; if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription } }
    }
}

struct DriveOperation: Identifiable { var id: String { item.id }; let item: Record; let folder: Bool }
struct DriveItemManager: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let operation: DriveOperation
    let changed: () -> Void
    @State private var name = ""
    @State private var move = false
    @State private var metadata = false
    @State private var previewFile: Record?
    @State private var pendingSensitiveFile: Record?
    @State private var confirmSensitive = false
    @State private var deleting = false
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                if operation.folder {
                    TextField("文件夹名称", text: $name)
                    Button("保存名称") { Task { await update(["name": .string(name)]) } }.disabled(name.isEmpty || name.count > 200)
                } else {
                    Text(operation.item["name"].string ?? "文件")
                    Button("查看与保存文件") { Task { await requestPreview() } }.accessibilityIdentifier("drive.preview.request")
                    if operation.item["isSensitive"].bool { Text("此文件标记为敏感媒体，确认后才会加载预览；不会移除敏感标记。").font(.caption) }
                    Button("名称、媒体说明与敏感标记") { metadata = true }
                }
                Button("移动到文件夹") { move = true }
                Button("删除", role: .destructive) { deleting = true }
                if let error { ErrorBanner(message: error) }
            }.puboForm().navigationTitle(operation.folder ? "管理文件夹" : "管理文件").disabled(busy)
                .toolbar { Button("关闭") { dismiss() } }.task { name = operation.item["name"].string ?? "" }
                .sheet(isPresented: $metadata) { AttachmentMetadataEditor(file: operation.item) { _ in changed(); dismiss() } }
                .sheet(item: $previewFile) { file in PublicAttachmentPreview(file: file, allowSensitive: file["isSensitive"].bool) }
                .alert("查看敏感文件？", isPresented: $confirmSensitive) {
                    Button("取消", role: .cancel) { pendingSensitiveFile = nil }.accessibilityIdentifier("drive.preview.cancel")
                    Button("查看文件") { previewFile = pendingSensitiveFile; pendingSensitiveFile = nil }.accessibilityIdentifier("drive.preview.confirm")
                } message: { Text("此操作会加载文件内容。敏感标记保持不变，保存文件仍需在预览页另行操作。") }
                .onChange(of: session.generation) { _, _ in pendingSensitiveFile = nil; previewFile = nil; confirmSensitive = false; dismiss() }
                .sheet(isPresented: $move) { NavigationStack { FolderDestinationPicker(excluding: operation.folder ? operation.id : nil) { id in move = false; Task { await update([operation.folder ? "parentId" : "folderId": id.map(JSONValue.string) ?? .null]) } } } }
                .confirmationDialog(operation.folder ? "删除此文件夹？服务器会检查它是否为空。" : "删除此文件？引用它的帖子可能无法再显示附件。", isPresented: $deleting) { Button("确认删除", role: .destructive) { Task { await remove() } } }
        }
    }
    private func requestPreview() async {
        guard !busy, !operation.folder else { return }
        busy = true; error = nil; defer { busy = false }
        let epoch = session.generation
        do {
            // Re-read metadata before deciding: a stale list must not bypass a newer sensitive flag.
            let value = try await session.call("drive/files/show", ["fileId": .string(operation.id)])
            guard epoch == session.generation, !Task.isCancelled else { return }
            guard value["id"].string == operation.id else { throw APIError.invalidResponse }
            let current = Record(value)
            if DriveMediaPolicy.requiresConfirmation(isSensitive: current["isSensitive"].bool) {
                pendingSensitiveFile = current; confirmSensitive = true
            } else { previewFile = current }
        } catch { if epoch == session.generation, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func update(_ fields: [String: JSONValue]) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var values = fields; values[operation.folder ? "folderId" : "fileId"] = .string(operation.id)
        do {
            do { _ = try await session.call(operation.folder ? "drive/folders/update" : "drive/files/update", values, mutation: true) }
            catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            let current = try await session.call(operation.folder ? "drive/folders/show" : "drive/files/show", [operation.folder ? "folderId" : "fileId": .string(operation.id)])
            guard fields.allSatisfy({ current[$0.key] == $0.value }) else { throw APIError.uncertain }
            changed(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func remove() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { _ = try await session.call(operation.folder ? "drive/folders/delete" : "drive/files/delete", [operation.folder ? "folderId" : "fileId": .string(operation.id)], mutation: true); changed(); dismiss() }
        catch { self.error = "请关闭此页并刷新列表，核对删除结果后再操作。" }
    }
}

struct FolderDestinationPicker: View {
    @Environment(AppSession.self) private var session
    var folderID: String? = nil
    var title = "网盘根目录"
    var excluding: String?
    let choose: (String?) -> Void
    @State private var folders: [Record] = []
    @State private var more = true
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Button("移动到此文件夹") { choose(folderID) }.disabled(folderID == excluding && excluding != nil)
            ForEach(folders.filter { $0.id != excluding }) { folder in NavigationLink { FolderDestinationPicker(folderID: folder.id, title: folder["name"].string ?? "文件夹", excluding: excluding, choose: choose) } label: { Label(folder["name"].string ?? "文件夹", systemImage: "folder") } }
            if more { Button("加载更多") { Task { await load() } }.disabled(busy) }
            if let error { ErrorBanner(message: error) }
        }.puboList().navigationTitle(title).task { if folders.isEmpty { await load() } }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { var fields: [String: JSONValue] = ["folderId": folderID.map(JSONValue.string) ?? .null, "limit": .number(30)]; if let last = folders.last { fields["untilId"] = .string(last.id) }; let page = Record.list(try await session.call("drive/folders", fields)); try Task.checkCancellation(); folders = Records.merge(folders, page, limit: 10_000); more = page.count == 30; error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
