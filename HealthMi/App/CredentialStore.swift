import Foundation
import Security

/// 小米凭据的 Keychain 存储。
enum CredentialStore {
    private static let service = "com.healthmi.HealthMi"
    /// 旧版 service 标识符（标识符统一前的值，用于一次性迁移）。
    private static let legacyService = "com.example.HealthMi"
    private static let userIdKey = "mi_fitness_user_id"
    private static let passTokenKey = "mi_fitness_pass_token"
    private static let migrationKey = "keychain_migrated_v1"

    /// 一次性迁移：把旧 service 下的凭据迁移到新 service。
    /// 在 App 启动时调用，已迁移过则跳过。
    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        // 新 service 下已有凭据则无需迁移
        if load() != nil {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        // 尝试从旧 service 读取
        guard let userId = get(key: userIdKey, service: legacyService),
              let passToken = get(key: passTokenKey, service: legacyService)
        else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        // 写入新 service
        do {
            try set(key: userIdKey, value: userId, service: service)
            try set(key: passTokenKey, value: passToken, service: service)
        } catch {
            // 写入失败不标记已迁移，下次启动重试
            return
        }
        // 删除旧 service 下的凭据
        try? delete(key: userIdKey, service: legacyService)
        try? delete(key: passTokenKey, service: legacyService)
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    static func save(userId: String, passToken: String) throws {
        try set(key: userIdKey, value: userId, service: service)
        try set(key: passTokenKey, value: passToken, service: service)
    }

    static func load() -> (userId: String, passToken: String)? {
        guard let userId = get(key: userIdKey, service: service),
              let passToken = get(key: passTokenKey, service: service)
        else {
            return nil
        }
        return (userId, passToken)
    }

    static func delete() {
        try? delete(key: userIdKey, service: service)
        try? delete(key: passTokenKey, service: service)
    }

    // MARK: - 底层

    private static func set(key: String, value: String, service: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    private static func get(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain 错误（\(status)）"
        }
    }
}
