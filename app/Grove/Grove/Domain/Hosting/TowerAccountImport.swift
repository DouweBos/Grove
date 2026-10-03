// Domain/Hosting/TowerAccountImport.swift
// Grove
//
// Migrates Tower's service accounts: the list lives in service-accounts-v3.plist, each token in Tower's Keychain item.

import Foundation
import GroveKit
import Security

nonisolated enum TowerAccountImport {

    struct Found: Hashable, Sendable {
        let kind: HostingServiceKind
        let host: String
        let username: String
        let organization: String?
        /// Tower's Keychain services to try, e.g. `Tower:GitHub:octocat:PersonalAccessToken`.
        let keychainServices: [String]
    }

    /// The user's real Application Support, even when Foundation's home is redirected for a test run.
    static var accountsFile: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/com.fournova.Tower3/service-accounts-v3.plist")
    }

    /// Reads only the account list; no secrets are touched until `token(for:)`.
    static func accounts() -> [Found] {
        (try? Data(contentsOf: accountsFile)).map(parse) ?? []
    }

    static func parse(_ data: Data) -> [Found] {
        guard let entries = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return [] }
        return entries.compactMap(found)
    }

    private static func found(_ entry: [String: Any]) -> Found? {
        guard let type = entry["serviceType"] as? String,
              let username = entry["username"] as? String, !username.isEmpty,
              let kind = kind(forTowerType: type) else { return nil }
        let api = (entry["serviceAPIURL"] as? String).flatMap(URL.init(string:))
        let method = entry["authenticationMethod"] as? String ?? ""
        let suffixes = [tokenSuffix(forMethod: method), method, "PersonalAccessToken", "OAuthToken", "AccessToken", "AppPassword", "Password"]
        var seen = Set<String>()
        let services = suffixes.filter { !$0.isEmpty && seen.insert($0).inserted }.map { "Tower:\(type):\(username):\($0)" }
        return Found(kind: kind, host: host(for: kind, api: api), username: username,
                     organization: kind == .azureDevOps ? azureOrganization(entry, api: api) : nil,
                     keychainServices: services)
    }

    private static func kind(forTowerType type: String) -> HostingServiceKind? {
        let type = type.lowercased()
        if type.hasPrefix("github") { return .github }
        if type.hasPrefix("gitlab") { return .gitlab }
        if type == "bitbucket" { return .bitbucket }
        if type.contains("azure") || type.contains("visualstudio") { return .azureDevOps }
        return nil
    }

    /// Tower records how it signed in; its Keychain item names the token kind differently.
    private static func tokenSuffix(forMethod method: String) -> String {
        switch method {
        case "PrivateToken": "PersonalAccessToken"
        case "OAuth", "OAuth2": "OAuthToken"
        default: ""
        }
    }

    /// `https://api.github.com/` is github.com; Enterprise and self-hosted APIs sit on the instance's own host.
    private static func host(for kind: HostingServiceKind, api: URL?) -> String {
        guard let host = api?.host?.lowercased() else { return kind.defaultHost }
        switch host {
        case "api.github.com": return "github.com"
        case "api.bitbucket.org": return "bitbucket.org"
        default: return host
        }
    }

    private static func azureOrganization(_ entry: [String: Any], api: URL?) -> String? {
        if let name = entry["accountName"] as? String, !name.isEmpty { return name }
        return api?.pathComponents.first { $0 != "/" }
    }

    /// Reads Tower's token; macOS asks the user to allow it the first time.
    static func token(for account: Found) -> String? {
        for service in account.keychainServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account.username,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty {
                return token
            }
        }
        return nil
    }
}

extension TowerAccountImport {

    struct Outcome: Equatable {
        var imported = 0
        /// Accounts that couldn't be carried over, with the reason.
        var failures: [String] = []
    }

    /// Copies each Tower account whose token still checks out into Grove; accounts Grove already has are left alone.
    @MainActor
    static func migrate(_ accounts: [Found], into store: HostingAccountStore, http: any HTTPClient = URLSessionHTTPClient(),
                        token: (Found) -> String? = token(for:)) async -> Outcome {
        var outcome = Outcome()
        for tower in accounts {
            let exists = store.accounts.contains {
                $0.kind == tower.kind && $0.host == tower.host && $0.username.lowercased() == tower.username.lowercased()
            }
            guard !exists else { continue }
            guard let secret = token(tower) else {
                outcome.failures.append("\(tower.username)@\(tower.host): its token isn\u{2019}t readable from the Keychain")
                continue
            }
            let draft = HostingAccount(kind: tower.kind, host: tower.host, username: tower.username, organization: tower.organization)
            do {
                let username = try await HostingAccountVerifier.whoAmI(RESTCredentials(account: draft, secret: secret), http: http)
                store.add(HostingAccount(kind: tower.kind, host: tower.host, username: username, organization: tower.organization),
                          secret: secret)
                outcome.imported += 1
            } catch {
                outcome.failures.append("\(tower.username)@\(tower.host): \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
