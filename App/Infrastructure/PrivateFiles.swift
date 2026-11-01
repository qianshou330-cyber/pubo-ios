import Foundation

/// Only removes app-owned preview/recording files; never deletes drive files on the server.
enum PrivateFiles {
    static func clear() throws {
        let directory = FileManager.default.temporaryDirectory
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard file.lastPathComponent.hasPrefix("pubo-private-") || file.lastPathComponent.hasPrefix("pubo-voice-") else { continue }
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
}
