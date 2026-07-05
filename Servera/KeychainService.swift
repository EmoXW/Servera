import Foundation
import Security

// MARK: - 凭据存储
// 所有服务器/NAS 密钥都存入 Keychain。SwiftData 记录只保存生成的标识，
// 避免导出文件和 UI 状态意外暴露敏感内容。

enum KeychainService {
    private static let service = "com.hs.Servera.credentials"

// 旧版单字段密钥辅助方法，为 NAS 密码兼容保留。
    static func saveSecret(_ secret: String, id: String = UUID().uuidString) throws -> DeviceCredentialRef {
        let data = Data(secret.utf8)
        return try saveData(data, id: id)
    }

// SSH 设备优先使用的凭据格式，可同时承载密码、私钥和私钥口令，
// 不需要继续给 SwiftData 增加敏感字段。
    static func saveCredentialBundle(_ bundle: DeviceCredentialBundle, id: String = UUID().uuidString) throws -> DeviceCredentialRef {
        let data = try JSONEncoder().encode(bundle)
        return try saveData(data, id: id)
    }

// 兼容旧备份/旧记录：过去的 Keychain 项可能只是一个 UTF-8 密码字符串。
    static func loadCredentialBundle(id: String) throws -> DeviceCredentialBundle? {
        guard let data = try loadData(id: id) else { return nil }
        if let bundle = try? JSONDecoder().decode(DeviceCredentialBundle.self, from: data) {
            return bundle
        }
        if let legacySecret = String(data: data, encoding: .utf8) {
            return DeviceCredentialBundle(password: legacySecret, privateKeyPEM: nil, privateKeyPassphrase: nil)
        }
        return nil
    }

    static func loadSecret(id: String) throws -> String? {
        guard let data = try loadData(id: id) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteSecret(id: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func saveData(_ data: Data, id: String) throws -> DeviceCredentialRef {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]

        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        return DeviceCredentialRef(id: id)
    }

    private static func loadData(id: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        return item as? Data
    }
}

// Keychain 错误保持简短且便于本地化；除非对诊断有帮助，否则调用方不应暴露原始状态码。
enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain 操作失败：\(status)"
        }
    }
}
