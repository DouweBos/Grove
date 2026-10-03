// Domain/Hosting/HostingAccounts.swift
// Grove
//
// Accounts Grove signs in to itself: service, host and username here, the token in the Keychain.

import Foundation
import GroveKit
import Observation
import Security

/// A signed-in account on a hosting service; its token lives in the Keychain under `id`.
nonisolated struct HostingAccount: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    let kind: HostingServiceKind
    /// `github.com`, a GitHub Enterprise or self-hosted GitLab host, `bitbucket.org` or `dev.azure.com`.
    var host: String
    /// The login the service reported when the token was checked.
    var username: String
    /// Azure DevOps organization the token belongs to.
    var organization: String?

    init(id: UUID = UUID(), kind: HostingServiceKind, host: String? = nil, username: String, organization: String? = nil) {
        self.id = id
        self.kind = kind
        self.host = (host ?? kind.defaultHost).lowercased()
        self.username = username
        self.organization = organization
    }

    var title: String {
        if let organization { return "\(username) (\(organization))" }
        return username
    }

    /// "GitHub", or "GitHub Enterprise" / "GitLab" with the host for self-hosted ones.
    var serviceTitle: String {
        host == kind.defaultHost ? kind.displayName : "\(kind.displayName) \u{00B7} \(host)"
    }

    /// Whether this account can reach the repository at `location`.
    func serves(_ location: RemoteLocation) -> Bool {
        guard location.kind == kind, location.host.caseInsensitiveCompare(host) == .orderedSame else { return false }
        if kind == .azureDevOps { return organization?.caseInsensitiveCompare(location.owner) == .orderedSame }
        return true
    }
}

extension HostingServiceKind {
    /// Where the public service lives; GitHub and GitLab can also be self-hosted.
    nonisolated var defaultHost: String {
        switch self {
        case .github: "github.com"
        case .gitlab: "gitlab.com"
        case .bitbucket: "bitbucket.org"
        case .azureDevOps: "dev.azure.com"
        }
    }
}

/// Where account secrets live; the Keychain in the app, a dictionary in tests.
nonisolated protocol SecretStore: Sendable {
    func secret(for account: UUID) -> String?
    func setSecret(_ secret: String?, for account: UUID)
}

/// One generic-password item per account, under a service name that says it's Grove's.
nonisolated struct KeychainSecretStore: SecretStore {
    static let defaultService = "Grove Hosting Account"
    let service: String

    init(service: String = defaultService) {
        self.service = service
    }

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
        add[kSecAttrLabel as String] = service
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// The accounts in Preferences > Accounts, shared by every window.
@MainActor
@Observable
final class HostingAccountStore {

    /// `-GroveKeychainService <name>` keeps a test run's tokens apart from the real ones.
    static let shared = HostingAccountStore(
        secrets: KeychainSecretStore(service: UserDefaults.standard.string(forKey: "GroveKeychainService")
                                     ?? KeychainSecretStore.defaultService),
        providesGitCredentials: true
    )

    private(set) var accounts: [HostingAccount] = []
    private let defaults: UserDefaults
    private let secrets: any SecretStore
    /// The app's store also answers git's HTTPS prompts; stores made for tests don't.
    private let providesGitCredentials: Bool
    private static let defaultsKey = "hostingAccounts"

    init(defaults: UserDefaults = .standard, secrets: any SecretStore = KeychainSecretStore(), providesGitCredentials: Bool = false) {
        self.defaults = defaults
        self.secrets = secrets
        self.providesGitCredentials = providesGitCredentials
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([HostingAccount].self, from: data) {
            accounts = stored
        }
        publishGitCredentials()
    }

    /// Adds the account, or replaces the one with the same id (re-authenticating) or the same service, host and user.
    func add(_ account: HostingAccount, secret: String) {
        let replaced = accounts.first {
            $0.id == account.id
                || ($0.kind == account.kind && $0.host == account.host && $0.username.caseInsensitiveCompare(account.username) == .orderedSame
                    && $0.organization == account.organization)
        }
        var stored = account
        if let replaced { stored.id = replaced.id }
        secrets.setSecret(secret, for: stored.id)
        if let index = accounts.firstIndex(where: { $0.id == stored.id }) {
            accounts[index] = stored
        } else {
            accounts.append(stored)
        }
        save()
    }

    func remove(_ account: HostingAccount) {
        secrets.setSecret(nil, for: account.id)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func secret(for account: HostingAccount) -> String? { secrets.secret(for: account.id) }

    func credentials(for account: HostingAccount) -> RESTCredentials? {
        secret(for: account).map { RESTCredentials(account: account, secret: $0) }
    }

    /// The first account that can reach `location`, with its token.
    func credentials(for location: RemoteLocation) -> RESTCredentials? {
        accounts.lazy.filter { $0.serves(location) }.compactMap(credentials(for:)).first
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.defaultsKey)
        publishGitCredentials()
    }

    private func publishGitCredentials() {
        guard providesGitCredentials else { return }
        GitCredentials.update(accounts.compactMap { account in secret(for: account).map { (account, $0) } })
    }
}

/// An account and its token, handed to an API client.
nonisolated struct RESTCredentials: Sendable {
    let account: HostingAccount
    let secret: String

    /// GitHub and GitLab take the token as a bearer; Bitbucket `username:app-password`, Azure DevOps an empty user and the PAT.
    var authorizationHeader: String {
        switch account.kind {
        case .github, .gitlab: "Bearer \(secret)"
        case .bitbucket: "Basic " + Data("\(account.username):\(secret)".utf8).base64EncodedString()
        case .azureDevOps: "Basic " + Data(":\(secret)".utf8).base64EncodedString()
        }
    }
}
