import SwiftUI
import UniformTypeIdentifiers
import Photos
import PUBOCore
import SDWebImage

struct AttachmentDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// A UIScrollView gives images system pinch/drag behavior instead of custom overlapping gestures.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = ImageScrollView(); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator
        let picture = UIImageView(image: image); picture.contentMode = .scaleAspectFit; picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(picture); scroll.picture = picture; context.coordinator.image = picture
        scroll.accessibilityLabel = "图片，可双指缩放和拖动"
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.image?.image = image
        if scroll.zoomScale == 1 { context.coordinator.image?.frame = scroll.bounds }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var image: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    }
    final class ImageScrollView: UIScrollView {
        weak var picture: UIImageView?
        override func layoutSubviews() {
            super.layoutSubviews()
            if zoomScale == 1 { picture?.frame = CGRect(origin: .zero, size: bounds.size); contentSize = bounds.size }
        }
    }
}

struct AttachmentPreviewContent: View {
    @Environment(AppSession.self) private var session
    let data: Data
    let url: URL
    let mime: String
    let name: String
    var gifImage: SDAnimatedImage? = nil
    var imagePreviewDisabled = false
    @State private var exporting = false
    @State private var saving = false
    @State private var feedback: String?
    @State private var active = true
    var body: some View {
        VStack(spacing: 12) {
            if let gifImage { PrivateGIFPlayer(image: gifImage, fullscreen: true) }
            else if imagePreviewDisabled { Label("此图片无法预览，原文件仍可保存。", systemImage: "photo.badge.exclamationmark").padding() }
            else if mime.hasPrefix("image/"), let image = UIImage(data: data) { ZoomableImage(image: image).frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 200) }
            else if mime.hasPrefix("audio/") || mime.hasPrefix("video/") { MediaPlayer(url: url).frame(minHeight: 180) }
            else { Label(name, systemImage: "doc").padding() }
            HStack {
                Button("保存到文件") { exporting = true }.frame(minHeight: 44).accessibilityIdentifier("attachment.saveFile")
                if mime.hasPrefix("image/") || mime.hasPrefix("video/") { Button(saving ? "正在保存…" : "保存到相册") { Task { await savePhoto() } }.disabled(saving).frame(minHeight: 44).accessibilityIdentifier("attachment.savePhoto") }
            }.padding(.horizontal)
            if let feedback { Text(feedback).font(.caption).padding(.horizontal).accessibilityIdentifier("attachment.feedback") }
        }.fileExporter(isPresented: $exporting, document: AttachmentDocument(data: data), contentType: UTType(mimeType: mime) ?? .data, defaultFilename: safeFilename) { result in
            guard active else { return }
            switch result { case .success: feedback = "文件已保存"; case .failure(let error): if (error as NSError).code != NSUserCancelledError { feedback = "保存未完成，请重试。" } }
        }.onAppear { active = true }.onDisappear { active = false; exporting = false }
    }
    private var safeFilename: String { String(name.replacingOccurrences(of: "[/\\\\:\\r\\n]", with: "_", options: .regularExpression).prefix(180)) }
    private func savePhoto() async {
        guard !saving, active else { return }; saving = true; defer { saving = false }
        let owner = session.generation
        if session.testMode { feedback = "隔离测试不写入系统相册"; return }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard active, owner == session.generation, !Task.isCancelled else { return }
        guard authorization == .authorized || authorization == .limited else { feedback = "未获得添加到相册权限；仍可选择保存到文件。"; return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if mime.hasPrefix("video/") { _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                else { _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
            }
            if active && owner == session.generation { feedback = "已保存到相册" }
        } catch { if active && owner == session.generation { feedback = "相册保存失败，请尝试保存到文件。" } }
    }
}

struct PublicAttachmentPreview: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let file: Record
    @State private var data: Data?
    @State private var localURL: URL?
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        NavigationStack {
            Group {
                if let data, let localURL { AttachmentPreviewContent(data: data, url: localURL, mime: file["type"].string ?? "application/octet-stream", name: file["name"].string ?? "PUBO附件") }
                else if let error { ErrorBanner(message: error) { retry += 1 } }
                else { ProgressView("加载原始文件…") }
            }.puboScreen().navigationTitle("查看附件").navigationBarTitleDisplayMode(.inline).toolbar { Button("关闭") { dismiss() } }
                .task(id: retry) { await load() }.onDisappear { clear() }
        }
    }
    private func load() async {
        guard !file["isSensitive"].bool, let source = safeMediaURL(file["url"].string) else { error = "无法在 App 打开此附件"; return }
        if session.testMode && !session.isolatedBackend { error = "隔离测试不下载外站媒体"; return }
        let epoch = session.generation
        do {
            guard file["size"].int <= 50 * 1024 * 1024 else { throw APIError(code: "FILE_TOO_LARGE", message: "附件超过 50 MiB，请在网页查看。") }
            let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForResource = 90
            let client = URLSession(configuration: configuration); defer { client.invalidateAndCancel() }
            let (temporary, response) = try await client.download(from: source)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard epoch == session.generation, !Task.isCancelled else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200, safeMediaURL(response.url?.absoluteString) != nil,
                  let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 50 * 1024 * 1024 else { throw APIError.invalidResponse }
            let content = try Data(contentsOf: temporary)
            let ext = UTType(mimeType: file["type"].string ?? "")?.preferredFilenameExtension ?? "bin"
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("pubo-private-\(UUID().uuidString).\(ext)")
            try content.write(to: destination, options: [.atomic, .completeFileProtection])
            clear(); localURL = destination; data = content; error = nil
        } catch { if epoch == session.generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func clear() { data = nil; if let localURL { try? FileManager.default.removeItem(at: localURL) }; localURL = nil }
}
