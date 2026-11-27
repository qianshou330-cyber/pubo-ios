import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import UIKit
import PUBOCore

/// Renders H5-aligned PUBO user QR codes (`#FBFFF0` quiet zone, `#455C00` rounded modules, `#0B1412` center PUBO badge).
/// Uses Level "H" error correction (30% recovery) and always keeps a light high-contrast quiet zone so scanners work in both light and dark modes.
enum PUBOQRCodeRenderer {
    static let cardBackgroundHex: UInt32 = 0xfbfff0
    static let moduleColorHex: UInt32 = 0x455c00
    static let badgeBackgroundHex: UInt32 = 0x0b1412

    private static let cardUIColor = uiColor(cardBackgroundHex)
    private static let moduleUIColor = uiColor(moduleColorHex)
    private static let badgeUIColor = uiColor(badgeBackgroundHex)
    private static let ciContext = CIContext(options: nil)

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: 1
        )
    }

    static func renderQRImage(for url: URL, pixelSize: CGFloat = 900) -> UIImage? {
        guard let matrix = qrMatrix(for: url.absoluteString) else { return nil }
        let n = matrix.count
        guard n >= 21 else { return nil }

        let quietModules: CGFloat = 4
        let totalModules = CGFloat(n) + quietModules * 2
        let moduleSize = pixelSize / totalModules
        let offset = quietModules * moduleSize

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cardUIColor.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

            // Draw the 3 rounded-square finder eyes (top-left, top-right, bottom-left).
            let finderOrigins = [(0, 0), (n - 7, 0), (0, n - 7)]
            for (fc, fr) in finderOrigins {
                drawFinder(
                    in: cg,
                    origin: CGPoint(x: offset + CGFloat(fc) * moduleSize, y: offset + CGFloat(fr) * moduleSize),
                    moduleSize: moduleSize
                )
            }

            // Reserve a centered quiet square for the PUBO logo (~22% of code side ≈ 4.8% area, well under Level H 30% limit).
            let centerIndex = Double(n) / 2.0
            let clearHalfModules = Double(n) * 0.115

            moduleUIColor.setFill()
            let dotInset = moduleSize * 0.06
            let dotSide = moduleSize - dotInset * 2
            let dotRadius = dotSide * 0.44
            for row in 0..<n {
                for col in 0..<n {
                    guard matrix[row][col] else { continue }
                    if isInsideFinder(col: col, row: row, size: n) { continue }
                    if abs(Double(col) + 0.5 - centerIndex) < clearHalfModules &&
                       abs(Double(row) + 0.5 - centerIndex) < clearHalfModules {
                        continue
                    }
                    let rect = CGRect(
                        x: offset + CGFloat(col) * moduleSize + dotInset,
                        y: offset + CGFloat(row) * moduleSize + dotInset,
                        width: dotSide,
                        height: dotSide
                    )
                    UIBezierPath(roundedRect: rect, cornerRadius: dotRadius).fill()
                }
            }

            // Center dark PUBO badge matching H5 QR page (`#0B1412` square + white PUBO wordmark).
            let codePixelSpan = CGFloat(n) * moduleSize
            let badgeSide = codePixelSpan * 0.19
            let badgeRect = CGRect(
                x: (pixelSize - badgeSide) / 2,
                y: (pixelSize - badgeSide) / 2,
                width: badgeSide,
                height: badgeSide
            )
            let haloRect = badgeRect.insetBy(dx: -moduleSize * 0.55, dy: -moduleSize * 0.55)
            cardUIColor.setFill()
            UIBezierPath(roundedRect: haloRect, cornerRadius: badgeSide * 0.16).fill()

            badgeUIColor.setFill()
            UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeSide * 0.10).fill()

            if let brand = UIImage(named: "Brand") {
                let targetWidth = badgeSide * 0.80
                let targetHeight = targetWidth * brand.size.height / max(1, brand.size.width)
                let logoRect = CGRect(
                    x: badgeRect.midX - targetWidth / 2,
                    y: badgeRect.midY - targetHeight / 2,
                    width: targetWidth,
                    height: targetHeight
                )
                brand.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: logoRect)
            }
        }
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

    private static func isInsideFinder(col: Int, row: Int, size n: Int) -> Bool {
        (col < 7 && row < 7) || (col >= n - 7 && row < 7) || (col < 7 && row >= n - 7)
    }

    private static func drawFinder(in cg: CGContext, origin: CGPoint, moduleSize m: CGFloat) {
        let outer = CGRect(x: origin.x, y: origin.y, width: 7 * m, height: 7 * m)
        let middle = outer.insetBy(dx: m, dy: m)
        let inner = outer.insetBy(dx: 2 * m, dy: 2 * m)

        moduleUIColor.setFill()
        UIBezierPath(roundedRect: outer, cornerRadius: 1.65 * m).fill()

        cardUIColor.setFill()
        UIBezierPath(roundedRect: middle, cornerRadius: 1.05 * m).fill()

        moduleUIColor.setFill()
        UIBezierPath(roundedRect: inner, cornerRadius: 0.68 * m).fill()
    }

    private static func qrMatrix(for text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let width = Int(output.extent.width.rounded())
        let height = Int(output.extent.height.rounded())
        guard width > 0, width == height,
              let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let gray = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        gray.interpolationQuality = .none
        gray.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var grid = Array(repeating: Array(repeating: false, count: width), count: height)
        for row in 0..<height {
            for col in 0..<width {
                grid[row][col] = pixels[row * width + col] < 128
            }
        }
        // Self-verify orientation: the 3 finder patterns MUST sit at top-left, top-right, bottom-left (never bottom-right).
        if finderScore(grid, col: width - 7, row: height - 7) > finderScore(grid, col: width - 7, row: 0) {
            grid.reverse()
        }
        return grid
    }

    private static func finderScore(_ grid: [[Bool]], col c0: Int, row r0: Int) -> Int {
        var score = 0
        for dr in 0..<7 {
            for dc in 0..<7 {
                let onBorder = dr == 0 || dr == 6 || dc == 0 || dc == 6
                let onCenter = (2...4).contains(dr) && (2...4).contains(dc)
                let expected = onBorder || onCenter
                if grid[r0 + dr][c0 + dc] == expected { score += 1 }
            }
        }
        return score
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
                            .interpolation(.none)
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
