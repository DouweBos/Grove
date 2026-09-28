// TowerAccountImportTests.swift
// GroveTests
//
// Tower's service accounts: reading the list without secrets, and importing one with its Keychain token.

import Foundation
import Testing
@testable import Grove

@MainActor
struct TowerAccountImportTests {

    private func plist(_ entries: [[String: Any]]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
    }

    @Test func readsTowersAccountsAndTheirKeychainItems() throws {
        let data = try plist([
            ["serviceType": "GitHub", "username": "octo", "authenticationMethod": "PrivateToken",
             "serviceAPIURL": "https://api.github.com/", "accountName": ""],
            ["serviceType": "GitHubEnterprise", "username": "dev", "authenticationMethod": "OAuth",
             "serviceAPIURL": "https://ghe.example.com/api/v3/"],
            ["serviceType": "GitLab", "username": "tanuki", "serviceAPIURL": "https://gitlab.example.com/api/v4/"],
            ["serviceType": "AzureDevOps", "username": "me", "serviceAPIURL": "https://dev.azure.com/contoso/"],
            ["serviceType": "Beanstalk", "username": "old"]
        ])
        let found = TowerAccountImport.parse(data)
        #expect(found.map(\.kind) == [.github, .github, .gitlab, .azureDevOps])
        #expect(found.map(\.host) == ["github.com", "ghe.example.com", "gitlab.example.com", "dev.azure.com"])
        #expect(found[0].keychainServices.first == "Tower:GitHub:octo:PersonalAccessToken")
        #expect(found[1].keychainServices.first == "Tower:GitHubEnterprise:dev:OAuthToken")
        #expect(found[3].organization == "contoso")
    }

    @Test func migratesAccountsWhoseTokenChecksOutAndSkipsKnownOnes() async {
        let store = makeAccountStore()
        store.add(HostingAccount(kind: .gitlab, host: "gitlab.com", username: "tanuki"), secret: "x")
        let octo = TowerAccountImport.Found(kind: .github, host: "github.com", username: "octo", organization: nil,
                                            keychainServices: ["Tower:GitHub:octo:PersonalAccessToken"])
        let known = TowerAccountImport.Found(kind: .gitlab, host: "gitlab.com", username: "tanuki", organization: nil, keychainServices: [])
        let outcome = await TowerAccountImport.migrate([octo, known], into: store,
                                                       http: FakeHTTPClient { _ in (200, #"{"login":"octo"}"#) },
                                                       token: { $0 == octo ? "ghp_tower" : nil })
        #expect(outcome == .init(imported: 1, failures: []))
        let imported = store.accounts.first { $0.kind == .github }
        #expect(imported?.username == "octo" && imported.flatMap(store.secret(for:)) == "ghp_tower")
    }

    @Test func anUnreadableOrRejectedTokenIsReportedAndSavesNothing() async {
        let store = makeAccountStore()
        let unreadable = TowerAccountImport.Found(kind: .github, host: "github.com", username: "a", organization: nil, keychainServices: [])
        let rejected = TowerAccountImport.Found(kind: .github, host: "ghe.example.com", username: "b", organization: nil, keychainServices: [])
        let outcome = await TowerAccountImport.migrate([unreadable, rejected], into: store,
                                                       http: FakeHTTPClient { _ in (401, "") },
                                                       token: { $0 == rejected ? "bad" : nil })
        #expect(outcome.imported == 0 && outcome.failures.count == 2)
        #expect(store.accounts.isEmpty)
    }
}
