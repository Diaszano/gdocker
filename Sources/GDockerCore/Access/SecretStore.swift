import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}

public enum SecretStoreError: Error, Equatable { case keychain(OSStatus) }

/// Generic-password items in the login keychain.
public struct KeychainSecretStore: SecretStore {
    private let service: String

    /// `GDOCKER_KEYCHAIN_SERVICE` exists for verification only. Every ad-hoc signed build has a new identity, and
    /// the keychain asks for authorization when a build reads an item another build created; a fresh service name
    /// per verification run means no old item is ever touched.
    public init(
        service: String = ProcessInfo.processInfo.environment["GDOCKER_KEYCHAIN_SERVICE"] ?? "com.diaszano.gdocker"
    ) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read(account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretStoreError.keychain(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let updated = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw SecretStoreError.keychain(updated) }
        var item = query(account)
        item[kSecValueData as String] = data
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw SecretStoreError.keychain(added) }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }
}
