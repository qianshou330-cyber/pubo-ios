import SwiftUI
import Photos
import UIKit
import PUBOCore

/// Thin UIKit wrapper around `PUBOCore.UserQRCodeRenderer` plus shareable portrait card composition.
enum PUBOQRCodeRenderer {
    static let cardBackgroundHex: UInt32 = UserQRCodeRenderer.cardBackgroundHex
    static let moduleColorHex: UInt32 = UserQRCodeRenderer.moduleColorHex
    static let badgeBackgroundHex: UInt32 = UserQRCodeRenderer.badgeBackgroundHex

    private static let cardUIColor = uiColor(cardBackgroundHex)

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: 1
        )
    }

    static func renderQRImage(for url: URL, pixelSize: CGFloat = 900) -> UIImage? {
        let brandLogo = UIImage(named: "Brand")?.cgImage
        guard let cgImage = UserQRCodeRenderer.renderCGImage(
            for: url,
            pixelSize: Int(pixelSize.rounded()),
            brandLogo: brandLogo
        ) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// Renders a clean shareable portrait card containing the QR code, display name, handle and PUBO mark.
    static func renderShareCard(qrImage: UIImage, displayName: String, handle: String?) -> UIImage {
        let size = CGSize(width: 1080, height: 1440)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            uiColor(0xf9f9f9).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Subtle bottom green dot-matrix matching the H5 card background.
            let dotColor = uiColor(0x86b300).withAlphaComponent(0.22)
            dotColor.setFill()
            let spacing: CGFloat = 42
            for row in stride(from: size.height * 0.72, through: size.height - 20, by: spacing) {
                let progress = (row - size.height * 0.72) / (size.height * 0.28)
                uiColor(0x86b300).withAlphaComponent(0.24 * progress).setFill()
                for col in stride(from: 24 as CGFloat, through: size.width - 24, by: spacing) {
                    cg.fillEllipse(in: CGRect(x: col, y: row, width: 6, height: 6))
                }
            }

            // Rounded QR card with soft shadow.
            let qrSide: CGFloat = 660
            let qrRect = CGRect(x: (size.width - qrSide) / 2, y: 200, width: qrSide, height: qrSide)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 12), blur: 32, color: UIColor.black.withAlphaComponent(0.08).cgColor)
            cardUIColor.setFill()
            UIBezierPath(roundedRect: qrRect, cornerRadius: 36).fill()
            cg.restoreGState()

            cg.saveGState()
            UIBezierPath(roundedRect: qrRect, cornerRadius: 36).addClip()
            qrImage.draw(in: qrRect)
            cg.restoreGState()

            // Name & handle.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: uiColor(0x2a2e2c),
                .paragraphStyle: paragraph
            ]
            (displayName as NSString).draw(in: CGRect(x: 80, y: qrRect.maxY + 72, width: size.width - 160, height: 64), withAttributes: nameAttrs)

            if let handle {
                let handleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 34, weight: .regular),
                    .foregroundColor: uiColor(0x777777),
                    .paragraphStyle: paragraph
                ]
                (handle as NSString).draw(in: CGRect(x: 80, y: qrRect.maxY + 146, width: size.width - 160, height: 48), withAttributes: handleAttrs)
            }

            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .regular),
                .foregroundColor: uiColor(0x8c938f),
                .paragraphStyle: paragraph
            ]
            ("使用 PUBO 扫一扫查看我的个人主页" as NSString).draw(
                in: CGRect(x: 80, y: qrRect.maxY + 216, width: size.width - 160, height: 40),
                withAttributes: hintAttrs
            )

            // Bottom PUBO brand mark.
            if let brand = UIImage(named: "Brand") {
                let bw: CGFloat = 210
                let bh = bw * brand.size.height / max(1, brand.size.width)
                let rect = CGRect(x: (size.width - bw) / 2, y: size.height - bh - 92, width: bw, height: bh)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 14, color: UIColor.black.withAlphaComponent(0.16).cgColor)
                brand.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: rect)
                cg.restoreGState()
            }
        }
    }
}

/// H5-aligned "My QR Code" identity card with top Scan pill, rounded green PUBO QR code, user avatar/handle, and save/share actions.
struct MyQRCodeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var allowScanSwitch = true
    var onScannedUser: ((String) -> Void)? = nil

    @State private var qrImage: UIImage?
    @State private var shareCard: UIImage?
    @State private var showScanner = false
    @State private var pendingScannedUserID: String?
    @State private var saving = false
    @State private var feedback: String?
    @State private var active = false

    private var user: Record? { session.user }
    private var qrURL: URL? { user.flatMap { UserQRCode.url(forUserID: $0.id) } }
    private var handle: String? { UserQRCode.displayHandle(username: user?["username"].string, host: user?["host"].string) }

    var body: some View {
        ZStack {
            PUBOTheme.background.ignoresSafeArea()
            bottomDotBackdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    if allowScanSwitch {
                        Button {
                            pendingScannedUserID = nil
                            showScanner = true
                        } label: {
                            Label("扫描", systemImage: "qrcode.viewfinder")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(PUBOTheme.text)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .background(PUBOTheme.button, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("myQR.scan")
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 12)

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 244, height: 244)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 18, y: 6)
                            .accessibilityLabel("我的 PUBO 二维码")
                            .accessibilityIdentifier("myQR.image")
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(red: 251/255, green: 255/255, blue: 240/255))
                            .frame(width: 244, height: 244)
                            .overlay { ProgressView() }
                    }

                    if let user {
                        VStack(spacing: 10) {
                            Avatar(user: user, size: 64)
                            Text(user.displayName)
                                .font(.title3.bold())
                                .foregroundStyle(PUBOTheme.text)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("myQR.displayName")
                            if let handle {
                                Text(verbatim: handle)
                                    .font(.subheadline)
                                    .foregroundStyle(PUBOTheme.secondary)
                                    .accessibilityIdentifier("myQR.handle")
                            }
                        }
                        .padding(.top, 4)
                    }

                    if let shareCard {
                        HStack(spacing: 12) {
                            Button {
                                Task { await saveCardToPhotos(shareCard) }
                            } label: {
                                Label(saving ? "正在保存…" : "保存图片", systemImage: "square.and.arrow.down")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .frame(minHeight: 44)
                                    .background(PUBOTheme.button, in: Capsule())
                                    .foregroundStyle(PUBOTheme.text)
                            }
                            .buttonStyle(.plain)
                            .disabled(saving)
                            .accessibilityIdentifier("myQR.save")

                            ShareLink(
                                item: Image(uiImage: shareCard),
                                preview: SharePreview((user?.displayName ?? "PUBO") + " 的二维码", image: Image(uiImage: shareCard))
                            ) {
                                Label("分享", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .frame(minHeight: 44)
                                    .background(PUBOTheme.button, in: Capsule())
                                    .foregroundStyle(PUBOTheme.text)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("myQR.share")
                        }
                        .padding(.top, 4)
                    }

                    if let feedback {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(PUBOTheme.secondary)
                            .accessibilityIdentifier("myQR.feedback")
                    }

                    Spacer(minLength: 28)

                    Image("Brand")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.28) : Color.white)
                        .frame(width: 96, height: 96 * 221 / 660)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 6, y: 2)
                        .padding(.bottom, 20)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("我的二维码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
                    .accessibilityIdentifier("myQR.close")
            }
        }
        .onAppear {
            active = true
            rebuildQRCode()
        }
        .onDisappear { active = false }
        .onChange(of: session.generation) { _, _ in
            showScanner = false
            pendingScannedUserID = nil
            rebuildQRCode()
        }
        .sheet(isPresented: $showScanner, onDismiss: {
            if let id = pendingScannedUserID {
                pendingScannedUserID = nil
                if let onScannedUser {
                    onScannedUser(id)
                    dismiss()
                }
            }
        }) {
            NavigationStack {
                FriendQRScannerView(allowSwitchToMyQR: false) { id in
                    pendingScannedUserID = id
                    showScanner = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showScanner = false }
                            .accessibilityIdentifier("scanner.close")
                    }
                }
            }
        }
    }

    private var bottomDotBackdrop: some View {
        VStack(spacing: 0) {
            Spacer()
            Canvas { context, size in
                let spacing: CGFloat = 24
                let dotSize: CGFloat = 3
                let baseAlpha: Double = colorScheme == .dark ? 0.18 : 0.24
                let rows = Int(size.height / spacing)
                let cols = Int(size.width / spacing)
                for r in 0...rows {
                    let progress = Double(r) / Double(max(1, rows))
                    let color = PUBOTheme.accent.opacity(baseAlpha * progress)
                    let y = CGFloat(r) * spacing
                    for c in 0...cols {
                        let x = CGFloat(c) * spacing + 12
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)), with: .color(color))
                    }
                }
            }
            .frame(height: 220)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func rebuildQRCode() {
        guard let url = qrURL else { qrImage = nil; shareCard = nil; return }
        let rendered = PUBOQRCodeRenderer.renderQRImage(for: url)
        qrImage = rendered
        if let rendered {
            shareCard = PUBOQRCodeRenderer.renderShareCard(
                qrImage: rendered,
                displayName: user?.displayName ?? "PUBO",
                handle: handle
            )
        } else {
            shareCard = nil
        }
    }

    private func saveCardToPhotos(_ image: UIImage) async {
        guard !saving, active else { return }
        saving = true
        defer { saving = false }
        let owner = session.generation
        if session.testMode {
            feedback = "隔离测试不写入系统相册"
            return
        }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard active, owner == session.generation, !Task.isCancelled else { return }
        guard authorization == .authorized || authorization == .limited else {
            feedback = "未获得添加到相册权限，可在 iPhone 设置中开启。"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            if active && owner == session.generation { feedback = "已保存到相册" }
        } catch {
            if active && owner == session.generation { feedback = "保存失败，请稍后重试。" }
        }
    }
}
