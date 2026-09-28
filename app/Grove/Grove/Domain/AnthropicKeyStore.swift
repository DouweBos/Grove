// Domain/AnthropicKeyStore.swift
// Grove
//
// The Anthropic API key for AI commit messages, kept in the login Keychain.

import Foundation
import Security

enum AnthropicKeyStore {

    static let service = "com.houwert.Grove.anthropic"

    /// `-GroveKeychainAccount <name>` points dev and test runs at their own entry, never the real key.
    static var account: String {
        UserDefaults.standard.string(forKey: "GroveKeychainAccount") ?? "api-key"
    }

    enum Failure: LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                "The Keychain refused the change (\(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"))."
            }
        }
    }

    static func key(account: String = account) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static var hasKey: Bool { key() != nil }

    static func save(_ key: String, account: String = account) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try delete(account: account) }
        let data = Data(trimmed.utf8)
        let update = SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = baseQuery(account: account)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Grove Anthropic API Key"
            let add = SecItemAdd(item as CFDictionary, nil)
            guard add == errSecSuccess else { throw Failure.keychain(add) }
        } else if update != errSecSuccess {
            throw Failure.keychain(update)
        }
    }

    static func delete(account: String = account) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
