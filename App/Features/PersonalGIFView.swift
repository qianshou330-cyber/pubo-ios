import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import SDWebImage
import PUBOCore

struct ChatEmojiPicker: View {
    let chooseEmoji: (String) -> Void
    let chooseGIF: (Data) -> Void
    @State private var collection = false
    var body: some View {
        VStack(spacing: 0) {
            Picker("表情类型", selection: $collection) { Text("表情").tag(false); Text("GIF 收藏").tag(true) }.pickerStyle(.segmented).padding()
            if collection { PersonalGIFView(choose: chooseGIF) }
            else { ReactionPicker(choose: chooseEmoji) }
        }.background(PUBOTheme.panel)
    }
}

private struct GIFPhotoTransfer: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            guard (try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= GIFStickerCodec.inputLimit else { throw GIFStickerError.tooLarge }
            return GIFPhotoTransfer(data: try Data(contentsOf: received.file))
        }
    }
}

struct PersonalGIFView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let choose: (Data) -> Void
    @State private var items: [LocalGIFSticker] = []
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var notice: String?
    @State private var problem: String?
    @State private var deleting: LocalGIFSticker?
    @State private var task: Task<Void, Never>?
    @State private var ownerID: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button { importing = true } label: { Label("添加 GIF", systemImage: "plus") }.accessibilityIdentifier("stickers.import")
                        Spacer()
                        PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) { Label("从相册添加", systemImage: "photo") }
                    }.buttonStyle(.bordered).disabled(busy)
                    Text("每张不超过 100KB，超出时自动压缩。压缩可能降低清晰度和帧率。").font(.caption).foregroundStyle(PUBOTheme.secondary)
                    if busy { ProgressView("正在处理 GIF…") }
                    if let notice { Text(notice).font(.callout).accessibilityIdentifier("stickers.notice") }
                    if let problem { Text(problem).font(.callout).foregroundStyle(.red).accessibilityIdentifier("stickers.error") }
                    if items.isEmpty && !busy { ContentUnavailableView("还没有收藏的 GIF", systemImage: "face.smiling", description: Text("长按聊天里的 GIF 收藏，或从文件、相册添加。")) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 16) {
                        ForEach(items) { item in
                            Button { select(item) } label: {
                                VStack(spacing: 4) { LocalGIFThumbnail(sticker: item).frame(height: 84); Text("\(Double(item.bytes) / 1000, specifier: "%.1f")KB").font(.caption2).foregroundStyle(PUBOTheme.secondary) }.frame(maxWidth: .infinity).padding(5).background(PUBOTheme.button, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("stickers.item." + item.id).accessibilityLabel("选择 GIF 表情包")
                                .contextMenu { Button("移除收藏", role: .destructive) { deleting = item } }
                        }
                    }
                    Text("点选后加入输入框，再点击发送。收藏仅保存在此 iPhone，按账号隔离；退出该账号或卸载 App 会清除。").font(.caption).foregroundStyle(PUBOTheme.secondary)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--sticker-import-testing") {
                        Button("测试导入超限 GIF") { start { GIFTestFixtures.compressible } }.accessibilityIdentifier("stickers.test.large")
                        Button("测试导入损坏 GIF") { start { Data("GIF89a broken".utf8) } }.accessibilityIdentifier("stickers.test.invalid")
                    }
                    #endif
                }.padding()
            }.puboScreen().navigationTitle("GIF 收藏").toolbar { Button("关闭") { dismiss() } }
        }.task(id: session.generation) { task?.cancel(); items = []; if ownerID == nil { ownerID = session.user?.id }; guard ownerID == session.user?.id else { dismiss(); return }; reload() }
            .onChange(of: session.user?.id) { _, _ in task?.cancel(); items = []; dismiss() }
            .onDisappear { task?.cancel(); items = [] }
            .onChange(of: phase) { _, value in if value == .background { task?.cancel(); items = [] } else if value == .active { reload() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.gif]) { result in
                switch result {
                case .success(let url): start {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= GIFStickerCodec.inputLimit else { throw GIFStickerError.tooLarge }
                    return try Data(contentsOf: url)
                }
                case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { problem = error.localizedDescription }
                }
            }
            .onChange(of: photo) { _, item in guard let item else { return }; start { guard let transfer = try await item.loadTransferable(type: GIFPhotoTransfer.self) else { throw GIFStickerError.invalid }; return transfer.data } }
            .confirmationDialog("移除这张本机收藏？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("移除收藏", role: .destructive) { if let deleting, let owner = session.user?.id { do { try session.gifStickers?.remove(deleting, account: owner); reload() } catch { problem = error.localizedDescription } }; deleting = nil }
            }
    }
    private func reload() {
        guard let account = session.user?.id, let vault = session.gifStickers else { items = []; problem = GIFStickerError.unavailable.localizedDescription; return }
        do { items = try vault.list(account: account) } catch { items = []; problem = error.localizedDescription }
    }
    private func start(_ read: @escaping @MainActor () async throws -> Data) {
        guard !busy, let account = session.user?.id, ownerID == account else { return }
        let epoch = session.generation; busy = true; notice = nil; problem = nil
        task = Task { @MainActor in
            defer { busy = false; photo = nil }
            do {
                let data = try await read(); try Task.checkCancellation()
                let prepared = try await GIFStickerCodec.prepare(data); try Task.checkCancellation()
                guard epoch == session.generation, account == session.user?.id, phase != .background else { return }
                guard let vault = session.gifStickers else { throw GIFStickerError.unavailable }
                let result = try vault.add(prepared, account: account)
                notice = result.inserted ? (prepared.wasCompressed ? "已自动压缩并添加 · \(prepared.data.count / 1000)KB" : "已添加 GIF") : "已经收藏过这张表情包"
                reload()
            } catch is CancellationError { }
            catch { if epoch == session.generation { problem = error.localizedDescription } }
        }
    }
    private func select(_ item: LocalGIFSticker) {
        guard let owner = session.user?.id, ownerID == owner, let vault = session.gifStickers else { return }
        do { let data = try vault.data(item, account: owner); choose(data); dismiss() } catch { problem = error.localizedDescription }
    }
}

private struct LocalGIFThumbnail: View {
    @Environment(AppSession.self) private var session
    let sticker: LocalGIFSticker
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let gif = image as? SDAnimatedImage { PrivateGIFPlayer(image: gif, maxInlineSize: CGSize(width: 82, height: 82)).allowsHitTesting(false) }
            else if let image { Image(uiImage: image).resizable().scaledToFit().frame(width: 82, height: 82) }
            else if failed { Image(systemName: "exclamationmark.triangle").accessibilityLabel("表情包读取失败") }
            else { ProgressView() }
        }.task(id: session.generation) {
            let epoch = session.generation; image = nil
            guard let account = session.user?.id, let vault = session.gifStickers else { return }
            do { let data = try vault.data(sticker, account: account); let decoded = try await PrivateImageDecoder.decode(data, maxPixel: 164); guard epoch == session.generation, !Task.isCancelled else { return }; image = decoded } catch { if !Task.isCancelled { failed = true } }
        }.onDisappear { image = nil }
    }
}
