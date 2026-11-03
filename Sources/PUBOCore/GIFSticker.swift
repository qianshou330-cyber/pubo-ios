import Foundation
import CryptoKit
import ImageIO
import CoreGraphics

public enum GIFStickerError: LocalizedError {
    case invalid, tooLarge, tooComplex, cannotCompress, unavailable, corruptStore
    public var errorDescription: String? {
        switch self {
        case .invalid: return "请选择有效的 GIF 文件。"
        case .tooLarge: return "原文件超过 50 MiB，请先缩小后再添加。"
        case .tooComplex: return "这张 GIF 的尺寸、帧数或时长过大，请选择更短的动图。"
        case .cannotCompress: return "无法在保留动画的情况下压缩至 100KB，请选择较小的 GIF。"
        case .unavailable: return "本机表情包存储不可用，请稍后重试。"
        case .corruptStore: return "本机表情包数据异常，请重新添加。"
        }
    }
}

public struct PreparedGIFSticker: Sendable {
    public let data: Data
    public let sourceSHA256: String
    public let wasCompressed: Bool
}

public enum GIFStickerCodec {
    public static let byteLimit = 100_000
    public static let inputLimit = 50 * 1024 * 1024
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func prepare(_ data: Data) async throws -> PreparedGIFSticker {
        let task = Task.detached(priority: .userInitiated) { try encode(data) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private static func encode(_ data: Data) throws -> PreparedGIFSticker {
        try Task.checkCancellation()
        guard data.count <= inputLimit else { throw GIFStickerError.tooLarge }
        guard ["GIF87a", "GIF89a"].contains(String(data: data.prefix(6), encoding: .ascii) ?? ""),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete else { throw GIFStickerError.invalid }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw GIFStickerError.invalid }
        guard count <= 2000,
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, Double(width) * Double(height) <= 40_000_000 else { throw GIFStickerError.tooComplex }
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let loop = (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount]
        var delays: [Double] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let raw = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
            guard raw.isFinite, raw >= 0 else { throw GIFStickerError.invalid }
            delays.append(raw < 0.02 ? 0.1 : raw)
        }
        guard delays.reduce(0, +) <= 600 else { throw GIFStickerError.tooComplex }
        let digest = Self.digest(data)
        if data.count <= byteLimit { return PreparedGIFSticker(data: data, sourceSHA256: digest, wasCompressed: false) }
        // Whole-duration frame groups: reduce resolution/frame rate, never truncate the clip.
        let attempts = [(320, 120), (256, 100), (224, 80), (192, 60), (160, 45), (128, 30), (96, 20), (72, 12), (48, 8)]
        for (pixels, cap) in attempts {
            try Task.checkCancellation()
            let result: Data? = try autoreleasepool {
                let frames = min(count, cap), buffer = NSMutableData()
                guard let output = CGImageDestinationCreateWithData(buffer, "com.compuserve.gif" as CFString, frames, nil) else { throw GIFStickerError.invalid }
                if let loop { CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loop]] as CFDictionary) }
                for frame in 0..<frames {
                    try Task.checkCancellation()
                    let first = frame * count / frames, end = (frame + 1) * count / frames
                    let duration = delays[first..<end].reduce(0, +)
                    let valid: Bool = autoreleasepool {
                        guard let image = CGImageSourceCreateThumbnailAtIndex(source, first, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), pixels), kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
                        CGImageDestinationAddImage(output, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: duration, kCGImagePropertyGIFUnclampedDelayTime: duration]] as CFDictionary)
                        return true
                    }
                    guard valid else { throw GIFStickerError.invalid }
                }
                guard CGImageDestinationFinalize(output) else { throw GIFStickerError.invalid }
                return buffer.length <= byteLimit ? buffer as Data : nil
            }
            if let result {
                guard let decoded = CGImageSourceCreateWithData(result as CFData, nil), CGImageSourceGetCount(decoded) == min(count, cap) else { throw GIFStickerError.invalid }
                try Task.checkCancellation()
                return PreparedGIFSticker(data: result, sourceSHA256: digest, wasCompressed: true)
            }
        }
        throw GIFStickerError.cannotCompress
    }
}

public struct LocalGIFSticker: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let sourceSHA256: String
    public let bytes: Int
    public let createdAt: Date
}

/// User-requested local copies, separate from transient private-attachment preview caches.
@MainActor public final class GIFStickerVault {
    private let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var resource = root, values = URLResourceValues(); values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        #endif
    }
    private func directory(_ account: String) throws -> URL {
        guard account.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { throw GIFStickerError.unavailable }
        let path = root.appendingPathComponent(account, isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path.path)
        #endif
        return path
    }
    private func validID(_ id: String) -> Bool { id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    public func list(account: String) throws -> [LocalGIFSticker] {
        let file = try directory(account).appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let values = try JSONDecoder().decode([LocalGIFSticker].self, from: Data(contentsOf: file))
        guard values.allSatisfy({ validID($0.id) && validID($0.sourceSHA256) && $0.bytes > 0 && $0.bytes <= GIFStickerCodec.byteLimit }), Set(values.map(\.id)).count == values.count else { throw GIFStickerError.corruptStore }
        return values
    }
    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    public func add(_ prepared: PreparedGIFSticker, account: String) throws -> (sticker: LocalGIFSticker, inserted: Bool) {
        guard !prepared.data.isEmpty, prepared.data.count <= GIFStickerCodec.byteLimit else { throw GIFStickerError.cannotCompress }
        var items = try list(account: account); let id = GIFStickerCodec.digest(prepared.data)
        if let existing = items.first(where: { $0.id == id || $0.sourceSHA256 == prepared.sourceSHA256 }) { return (existing, false) }
        let entry = LocalGIFSticker(id: id, sourceSHA256: prepared.sourceSHA256, bytes: prepared.data.count, createdAt: Date())
        let folder = try directory(account), file = folder.appendingPathComponent(id + ".gif")
        try write(prepared.data, to: file); items.insert(entry, at: 0)
        do { try write(JSONEncoder().encode(items), to: folder.appendingPathComponent("index.json")) }
        catch { try? FileManager.default.removeItem(at: file); throw error }
        return (entry, true)
    }
    public func data(_ sticker: LocalGIFSticker, account: String) throws -> Data {
        guard try list(account: account).contains(sticker) else { throw GIFStickerError.unavailable }
        let file = try directory(account).appendingPathComponent(sticker.id + ".gif")
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= GIFStickerCodec.byteLimit else { throw GIFStickerError.corruptStore }
        let data = try Data(contentsOf: file)
        guard data.count == sticker.bytes, GIFStickerCodec.digest(data) == sticker.id else { throw GIFStickerError.corruptStore }
        return data
    }
    public func remove(_ sticker: LocalGIFSticker, account: String) throws {
        var items = try list(account: account); guard items.contains(sticker) else { return }; items.removeAll { $0.id == sticker.id }
        let folder = try directory(account)
        try write(JSONEncoder().encode(items), to: folder.appendingPathComponent("index.json"))
        let file = folder.appendingPathComponent(sticker.id + ".gif")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    public func clear(account: String) throws { try FileManager.default.removeItem(at: directory(account)) }
}
