import SwiftUI
import AVFoundation
import PUBOCore

/// Embed in a NavigationStack/sheet. The caller owns dismissal and profile presentation.
struct FriendQRScannerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    let onUser: (String) -> Void
    @State private var authorized = false
    @State private var checked = false
    @State private var error: String?
    @State private var accepted = false
    @State private var visible = false
    @State private var ownerGeneration: UUID?
    @State private var captureEpoch = UUID()
    var body: some View {
        let epoch = captureEpoch
        VStack(spacing: 20) {
            if authorized && visible && phase == .active && !accepted {
                UserQRPreview(onCode: { receive($0, epoch: epoch) }, onFailure: {
                    guard visible, phase == .active, epoch == captureEpoch, ownerGeneration == session.generation else { return }
                    error = $0; authorized = false
                }).id(epoch)
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("用户二维码取景器")
            } else if !checked { ProgressView("正在检查相机权限") }
            else { Image(systemName: "qrcode.viewfinder").font(.system(size: 64)).foregroundStyle(.secondary) }
            Text("扫描 PUBO 用户二维码").font(.headline)
            Text("仅识别本站用户二维码。识别后先查看资料，不会自动关注。").font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.secondary).accessibilityIdentifier("scanner.error") }
            if checked && !authorized && !session.testMode {
                Button("重新检查相机权限") { Task { await requestCamera() } }.accessibilityIdentifier("scanner.retryPermission")
            }
            NavigationLink("改用用户名搜索") { AddFriendView() }.accessibilityIdentifier("scanner.username")
        }.padding().navigationTitle("扫一扫")
            .onAppear { visible = true; ownerGeneration = session.generation; captureEpoch = UUID() }
            .onDisappear { visible = false; captureEpoch = UUID() }
            .task(id: visible) { if visible { await requestCamera() } }
            .onChange(of: phase) { _, _ in captureEpoch = UUID() }
            .onChange(of: session.generation) { _, _ in accepted = true; authorized = false; captureEpoch = UUID() }
    }
    private func requestCamera() async {
        // UI fixtures must never show a real system permission alert or start hardware capture.
        if session.testMode { checked = true; error = "演示测试不启用相机，请使用用户名搜索。"; return }
        let generation = session.generation
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard visible, !Task.isCancelled, generation == session.generation, ownerGeneration == generation else { return }
        checked = true; authorized = allowed; error = nil
        if !allowed { error = "未获得相机权限。可在系统设置中允许相机，或改用用户名搜索。" }
    }
    private func receive(_ code: String, epoch: UUID) {
        guard visible, phase == .active, epoch == captureEpoch, ownerGeneration == session.generation, !accepted else { return }
        guard let id = UserQRCode.userID(from: code) else { error = "这不是有效的 PUBO 用户二维码。请扫描用户主页二维码。"; return }
        accepted = true; onUser(id)
    }
}

private struct UserQRPreview: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void
    let onFailure: @MainActor (String) -> Void
    func makeUIViewController(context: Context) -> UserQRController { UserQRController(onCode: onCode, onFailure: onFailure) }
    func updateUIViewController(_ controller: UserQRController, context: Context) { }
    static func dismantleUIViewController(_ controller: UserQRController, coordinator: ()) { controller.stop() }
}

@MainActor
private final class UserQRController: UIViewController {
    private let driver: UserQRCaptureDriver
    private var preview: AVCaptureVideoPreviewLayer?
    init(onCode: @escaping @MainActor (String) -> Void, onFailure: @escaping @MainActor (String) -> Void) {
        driver = UserQRCaptureDriver(onCode: onCode, onFailure: onFailure)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: driver.session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview); self.preview = preview
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); driver.start() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stop() }
    func stop() { driver.stop() }
}

/// Not a UIKit type: every mutable capture property is confined to this serial queue.
/// Only the immutable session reference is shared with the main-thread preview layer.
private final class UserQRCaptureDriver: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.bolubo.native.user-qr")
    private let onCode: @MainActor (String) -> Void
    private let onFailure: @MainActor (String) -> Void
    private var configured = false
    private var stopped = true
    init(onCode: @escaping @MainActor (String) -> Void, onFailure: @escaping @MainActor (String) -> Void) {
        self.onCode = onCode; self.onFailure = onFailure
        super.init()
    }
    func start() {
        queue.async { [self] in
            stopped = false
            do {
                if !configured { try configure() }
                if !stopped && !session.isRunning { session.startRunning() }
            } catch {
                let callback = onFailure
                DispatchQueue.main.async { callback("当前设备无法使用相机，请改用用户名搜索。") }
            }
        }
    }
    func stop() {
        queue.async { [self] in
            stopped = true
            if session.isRunning { session.stopRunning() }
        }
    }
    private func configure() throws {
        guard let camera = AVCaptureDevice.default(for: .video) else { throw ScannerError.unavailable }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw ScannerError.unavailable }
        session.addInput(input); session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: queue)
        guard output.availableMetadataObjectTypes.contains(.qr) else { throw ScannerError.unavailable }
        output.metadataObjectTypes = [.qr]
        configured = true
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !stopped, let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        let callback = onCode
        // A queued delivery is checked again by the SwiftUI visibility/account/epoch gate.
        DispatchQueue.main.async { callback(value) }
    }
    private enum ScannerError: Error { case unavailable }
}
