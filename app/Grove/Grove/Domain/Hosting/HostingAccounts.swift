// Domain/Hosting/HostingAccounts.swift
// Grove
//
// Accounts for services reached over REST (Bitbucket, Azure DevOps). GitHub and GitLab sign in through their CLIs.

import Foundation
import Observation
import Security

/// A signed-in account on a REST-backed service; its token lives in the Keychain under `id`.
nonisolated struct HostingAccount: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    let kind: HostingServiceKind
    /// Bitbucket username or Atlassian email; an Azure DevOps display name.
    let username: String
    /// Azure DevOps organization the token belongs to.
    var organization: String?

    var title: String {
        if let organization { return "\(username) (\(organization))" }
        return username
    }

    /// Whether this account can reach the repository at `location`.
    func serves(_ location: RemoteLocation) -> Bool {
        guard location.kind == kind else { return false }
        if kind == .azureDevOps { return organization?.caseInsensitiveCompare(location.owner) == .orderedSame }
        return true
    }
}

/// Where account secrets live; the Keychain in the app, a dictionary in tests.
nonisolated protocol SecretStore: Sendable {
    func secret(for account: UUID) -> String?
    func setSecret(_ secret: String?, for account: UUID)
}

nonisolated struct KeychainSecretStore: SecretStore {
    private let service = "com.houwert.grove.hosting-accounts"

    func secret(for account: UUID) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account.uuidString, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ secret: String?, for account: UUID) {
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account.uuidString]
        SecItemDelete(match as CFDictionary)
        guard let secret else { return }
        var add = match
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// The REST accounts added in Preferences > Accounts, shared by every window.
@MainActor
@Observable
final class HostingAccountStore {

    static let shared = HostingAccountStore()

    private(set) var accounts: [HostingAccount] = []
    private let defaults: UserDefaults
    private let secrets: any SecretStore
    private static let defaultsKey = "hostingAccounts"

    init(defaults: UserDefaults = .standard, secrets: any SecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([HostingAccount].self, from: data) {
            accounts = stored
        }
    }

    func add(_ account: HostingAccount, secret: String) {
        secrets.setSecret(secret, for: account.id)
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        save()
    }

    func remove(_ account: HostingAccount) {
        secrets.setSecret(nil, for: account.id)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func secret(for account: HostingAccount) -> String? { secrets.secret(for: account.id) }

    /// The first account that can reach `location`, with its token.
    func credentials(for location: RemoteLocation) -> RESTCredentials? {
        for account in accounts where account.serves(location) {
            if let secret = secret(for: account) { return RESTCredentials(account: account, secret: secret) }
        }
        return nil
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.defaultsKey)
    }
}

/// An account and its token, handed to a REST client.
nonisolated struct RESTCredentials: Sendable {
    let account: HostingAccount
    let secret: String

    /// Bitbucket takes `username:app-password`, Azure DevOps an empty user and the PAT.
    var authorizationHeader: String {
        let user = account.kind == .azureDevOps ? "" : account.username
        return "Basic " + Data("\(user):\(secret)".utf8).base64EncodedString()
    }
}
