import Foundation
import Security
import BlackBoxCore

struct KeychainStore {
    private let service = "com.kellen.blackbox.credentials"
    func get(_ account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw BBError.setup("Keychain read failed (\(status)).") }
        return item as? Data
    }
    func set(_ value: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = value
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw BBError.setup("Keychain write failed.") }
        } else if status != errSecSuccess { throw BBError.setup("Keychain update failed (\(status)).") }
    }
    func delete(_ account: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else { throw BBError.setup("Keychain deletion failed.") }
    }
    func string(_ account: String) throws -> String { try get(account).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    func save<T: Encodable>(_ item: T, account: String) throws { try set(JSONEncoder().encode(item), account: account) }
    func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? { try get(account).map { try JSONDecoder().decode(type, from: $0) } }
}
