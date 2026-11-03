import Foundation
import Security
import PUBOCore

enum KeychainStore {
    private static let service = "com.bolubo.native.session"
    private static func query(_ account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    private static func read(_ account: String) throws -> Data? {
        var query = query(account); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError() }; return data
    }
    static func vault() throws -> AccountVault {
        if let data = try read("vault") { return try JSONDecoder().decode(AccountVault.self, from: data) }
        guard let data = try read("active") else { return AccountVault() }
        let migrated = AccountVault(legacy: try JSONDecoder().decode(LoginSecret.self, from: data))
        try write(migrated)
        guard let saved = try read("vault"), try JSONDecoder().decode(AccountVault.self, from: saved) == migrated else { throw KeychainError() }
        let status = SecItemDelete(query("active") as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError() }
        return migrated
    }
    static func load() throws -> LoginSecret? { try vault().active }
    static func save(_ value: LoginSecret) throws { var saved = try vault(); saved.install(value); try write(saved) }
    static func remove(_ id: String) throws { var saved = try vault(); saved.remove(id); try write(saved) }
    private static func write(_ vault: AccountVault) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(vault), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let query = query("vault"); let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; attributes.forEach { add[$0.key] = $0.value }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw KeychainError() }
        } else if status != errSecSuccess { throw KeychainError() }
    }
    struct KeychainError: LocalizedError { var errorDescription: String? { "无法安全保存登录信息，请解锁设备后重试。" } }
}
