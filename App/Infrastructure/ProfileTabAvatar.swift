import Foundation
import UIKit
import ImageIO

private final class AvatarRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}

/// Tab items accept rendered images. Fetch only public avatar bytes, without account credentials.
@MainActor enum ProfileTabAvatar {
    static func load(_ url: URL) async -> UIImage? {
        guard let data = await download(url), !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                 kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 84] as CFDictionary) else { return nil }
        return rounded(UIImage(cgImage: image))
    }

    private nonisolated static func download(_ url: URL) async -> Data? {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = URLCache.shared
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        let client = URLSession(configuration: config, delegate: AvatarRedirectGuard(), delegateQueue: nil)
        defer { client.invalidateAndCancel() }
        do {
            let (bytes, response) = try await client.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.mimeType?.hasPrefix("image/") == true, response.expectedContentLength <= 2_000_000 else { return nil }
            var data = Data()
            for try await byte in bytes {
                if Task.isCancelled || data.count >= 2_000_000 { return nil }
                data.append(byte)
            }
            return Task.isCancelled ? nil : data
        } catch { return nil }
    }

    static func rounded(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 26, height: 26)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2,
                                  width: scaled.width, height: scaled.height))
        }.withRenderingMode(.alwaysOriginal)
    }
}
