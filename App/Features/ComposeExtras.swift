import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PUBOCore

struct UserPicker: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let choose: (Record) -> Void
    @State private var query = ""
    @State private var users: [Record] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                TextField("搜索用户名或昵称", text: $query).textInputAutocapitalization(.never).accessibilityIdentifier("userPicker.query")
                ForEach(users) { user in Button { choose(user); dismiss() } label: { HStack { Avatar(user: user); VStack(alignment: .leading) { Text(user.displayName); Text("@" + (user["username"].string ?? "")).font(.caption) } } } }
                if let error { ErrorBanner(message: error) }
            }.puboList().navigationTitle("选择用户").toolbar { Button("关闭") { dismiss() } }
                .task(id: query) {
                    users = []; error = nil
                    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    do { try await Task.sleep(for: .milliseconds(300)); let values = Record.list(try await session.call("users/search", ["query": .string(String(query.prefix(100))), "limit": .number(30), "origin": .string("local")])); try Task.checkCancellation(); users = values }
                    catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
        }
    }
}

struct AttachmentMetadataEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let file: Record
    let saved: (Record) -> Void
    @State private var comment = ""
    @State private var sensitive = false
    @State private var error: String?
    @State private var busy = false
    @State private var uncertain = false
    var body: some View {
        NavigationStack {
            Form {
                Text(file["name"].string ?? "附件")
                TextField("媒体说明", text: $comment, axis: .vertical).lineLimit(3...8)
                Toggle("敏感媒体", isOn: $sensitive)
                Text("文件说明和敏感标记也会影响其他引用此文件的帖子。").font(.footnote)
                if let error { ErrorBanner(message: error) }
                Button(uncertain ? "核对文件最新状态" : "保存") { Task { await save() } }.disabled(busy || comment.count > 512)
            }.puboForm().navigationTitle("媒体设置").toolbar { Button("关闭") { dismiss() }.disabled(busy) }
                .task { comment = file["comment"].string ?? ""; sensitive = file["isSensitive"].bool }
        }
    }
    private func save() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if !uncertain {
                do { _ = try await session.call("drive/files/update", ["fileId": .string(file.id), "comment": .string(comment), "isSensitive": .bool(sensitive)], mutation: true) }
                catch { if (error as? APIError)?.code == "OUTCOME_UNKNOWN" { uncertain = true } else { throw error } }
            }
            let current = Record(try await session.call("drive/files/show", ["fileId": .string(file.id)]))
            guard current.id == file.id else { throw APIError.invalidResponse }
            guard (current["comment"].string ?? "") == comment, current["isSensitive"].bool == sensitive else { uncertain = false; throw APIError(code: "FILE_CHANGED", message: "最新文件设置与预期不同；已保留输入，请核对后再保存。") }
            saved(current); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    let finished: (Result<(Data, String, String), Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera
        controller.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]; controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let finished: (Result<(Data, String, String), Error>) -> Void
        init(_ finished: @escaping (Result<(Data, String, String), Error>) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(.failure(CancellationError())) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            do {
                if let url = info[.mediaURL] as? URL {
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "拍摄文件超过 50 MiB。") }
                    finished(.success((try Data(contentsOf: url), "拍摄视频.mov", "video/quicktime")))
                } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9), data.count <= 50 * 1024 * 1024 {
                    finished(.success((data, "拍摄照片.jpg", "image/jpeg")))
                } else { throw APIError.invalidResponse }
            } catch { finished(.failure(error)) }
        }
    }
}

struct ComposeSuggestions: View {
    @Environment(AppSession.self) private var session
    @Binding var text: String
    @State private var values: [String] = []
    private var suffix: String { String(text.split(whereSeparator: { $0.isWhitespace }).last ?? "") }
    var body: some View {
        ScrollView(.horizontal) { HStack { ForEach(values, id: \.self) { value in Button(value) { text = String(text.dropLast(suffix.count)) + value + " "; values = [] }.buttonStyle(.bordered) } } }
            .task(id: suffix) {
                values = []
                guard suffix.count >= 2 && suffix.count <= 80, suffix.hasPrefix("@") || suffix.hasPrefix("#") else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    let token = suffix
                    let response = try await session.call(token.hasPrefix("@") ? "users/search" : "hashtags/search", ["query": .string(String(token.dropFirst())), "limit": .number(8)])
                    try Task.checkCancellation(); guard token == suffix else { return }
                    values = token.hasPrefix("@") ? Record.list(response).map { "@" + ($0["username"].string ?? "") + ($0["host"].string.map { "@" + $0 } ?? "") } : response.array.compactMap(\.string).map { "#" + $0 }
                } catch { }
            }
    }
}
