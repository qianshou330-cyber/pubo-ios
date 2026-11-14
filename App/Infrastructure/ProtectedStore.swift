import Foundation
import PUBOCore

final class ProtectedStore {
    private let root: URL
    private let writes = OrderedSnapshotQueue()
    init(directory: URL? = nil) throws {
        if let directory { root = directory }
        else { root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PUBO", isDirectory: true) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var value = root
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try value.setResourceValues(attributes)
    }
    private func file(account: String, key: String) throws -> URL {
        guard account.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil,
              key.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { throw APIError.invalidResponse }
        let directory = root.appendingPathComponent(account, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        return directory.appendingPathComponent(key + ".json")
    }
    func read<T: Decodable>(_ type: T.Type, account: String, key: String) throws -> T? {
        return try writes.sync {
        let url = try file(account: account, key: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        }
    }
    func save<T: Encodable>(_ value: T, account: String, key: String) throws {
        try writes.sync {
            try JSONEncoder().encode(value).write(to: file(account: account, key: key), options: [.atomic, .completeFileProtection])
        }
    }
    // Only immutable value snapshots should enter this API. The queue coalesces
    // pending snapshots per key and serializes them with clear/read/save.
    func saveSnapshot<T: Encodable & Sendable>(_ value: T, account: String, key: String) {
        writes.submit(key: account + ":" + key) { [self] in
            try? JSONEncoder().encode(value).write(to: file(account: account, key: key), options: [.atomic, .completeFileProtection])
        }
    }
    func cancelPendingSnapshots() { writes.cancelPending() }
    func clear(account: String) throws {
        try writes.sync {
        guard account.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { throw APIError.invalidResponse }
        let directory = root.appendingPathComponent(account, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
    }
}
