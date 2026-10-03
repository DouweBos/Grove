// AccountSignInTests.swift
// GroveTests

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct AccountSignInTests {

    // MARK: Who am I

    @Test func whoAmIUsesEachServicesUserEndpoint() async throws {
        let http = FakeHTTPClient { request in
            switch request.url?.host {
            case "api.github.com": (200, #"{"login":"octo"}"#)
            case "ghe.example.com": (200, #"{"login":"corp-octo"}"#)
            default: (200, #"{"username":"tanuki"}"#)
            }
        }
        let github = HostingAccount(kind: .github, username: "")
        #expect(try await HostingAccountVerifier.whoAmI(RESTCredentials(account: github, secret: "t"), http: http) == "octo")
        let enterprise = HostingAccount(kind: .github, host: "GHE.example.com", username: "")
        #expect(try await HostingAccountVerifier.whoAmI(RESTCredentials(account: enterprise, secret: "t"), http: http) == "corp-octo")
        let gitlab = HostingAccount(kind: .gitlab, host: "gitlab.example.com", username: "")
        #expect(try await HostingAccountVerifier.whoAmI(RESTCredentials(account: gitlab, secret: "t"), http: http) == "tanuki")
        #expect(http.requests.map { $0.url?.absoluteString ?? "" } == [
            "https://api.github.com/user", "https://ghe.example.com/api/v3/user", "https://gitlab.example.com/api/v4/user"
        ])
        #expect(http.requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer t" })
    }

    @Test func accountsMatchTheirHost() {
        let enterprise = HostingAccount(kind: .github, host: "ghe.example.com", username: "me")
        #expect(enterprise.serves(RemoteLocation(kind: .github, host: "ghe.example.com", owner: "o", name: "r")))
        #expect(!enterprise.serves(RemoteLocation(kind: .github, host: "github.com", owner: "o", name: "r")))
        #expect(enterprise.serviceTitle == "GitHub \u{00B7} ghe.example.com")
        #expect(HostingAccount(kind: .gitlab, username: "me").serviceTitle == "GitLab")
    }

    // MARK: Adding

    @Test func tokenFormFillsTheUsernameFromTheService() async {
        let http = FakeHTTPClient { _ in (200, #"{"login":"octo"}"#) }
        let viewModel = AccountsViewModel(store: makeAccountStore(), http: http)
        viewModel.beginAdding(.githubEnterprise)
        viewModel.updateForm { $0.token = "tok" }
        #expect(viewModel.form?.canSubmit == false, "Enterprise needs a host")
        viewModel.updateForm { $0.host = "https://GHE.example.com/some/path" }
        await viewModel.submitForm()
        #expect(viewModel.form == nil)
        let account = viewModel.accounts.first
        #expect(account?.host == "ghe.example.com" && account?.username == "octo")
        #expect(account.flatMap(viewModel.store.secret(for:)) == "tok")
    }

    @Test func reauthenticatingKeepsTheAccountAndReplacesTheToken() async throws {
        let store = makeAccountStore()
        store.add(HostingAccount(kind: .github, username: "octo"), secret: "old")
        let original = try #require(store.accounts.first)
        let viewModel = AccountsViewModel(store: store, http: FakeHTTPClient { _ in (200, #"{"login":"octo"}"#) })
        viewModel.beginReauthenticating(original)
        #expect(viewModel.form?.replacing == original.id && viewModel.form?.provider == .github)
        viewModel.updateForm { $0.token = "new" }
        await viewModel.submitForm()
        #expect(store.accounts.count == 1 && store.accounts.first?.id == original.id)
        #expect(store.secret(for: original) == "new")
    }

    @Test func checkMarksBadTokens() async {
        let store = makeAccountStore()
        store.add(HostingAccount(kind: .github, username: "octo"), secret: "expired")
        let viewModel = AccountsViewModel(store: store, http: FakeHTTPClient { _ in (401, "") })
        viewModel.cliLogins = { [] }
        await viewModel.check()
        if case .failed = viewModel.statuses[store.accounts[0].id] {} else { Issue.record("expected a failed status") }
    }

    // MARK: Importing

    @Test func importOffersOnlyNewCLILoginsAndLeavesTheCLIAlone() async {
        let store = makeAccountStore()
        store.add(HostingAccount(kind: .gitlab, username: "tanuki"), secret: "x")
        let viewModel = AccountsViewModel(store: store, http: FakeHTTPClient { _ in (200, #"{"login":"octo"}"#) })
        viewModel.cliLogins = {
            [.init(kind: .github, host: "github.com", token: "gho_1"), .init(kind: .gitlab, host: "gitlab.com", token: "glpat")]
        }
        await viewModel.check()
        #expect(viewModel.importable.map(\.host) == ["github.com"])
        await viewModel.importLogin(viewModel.importable[0])
        #expect(viewModel.importable.isEmpty)
        let imported = store.accounts.first { $0.kind == .github }
        #expect(imported?.username == "octo" && imported.flatMap(store.secret(for:)) == "gho_1")
    }

    @Test func parsesCLILogins() {
        let status = """
        github.com
          ✓ Logged in to github.com account octo (keyring)
          - Active account: true
        ghe.example.com
          X Failed to log in to ghe.example.com account corp (keyring)
        """
        #expect(CLITokenImport.parseGitHubHosts(status) == ["github.com", "ghe.example.com"])
        let yaml = """
        git_protocol: ssh
        hosts:
          gitlab.com:
            token: glpat-abc
            api_host: gitlab.com
          gitlab.example.com:
            token: "glpat-def"
          keyring.example.com:
            token: !!null
        editor: vim
        """
        #expect(CLITokenImport.parseGitLabConfig(yaml) == [
            .init(kind: .gitlab, host: "gitlab.com", token: "glpat-abc"), .init(kind: .gitlab, host: "gitlab.example.com", token: "glpat-def")
        ])
    }

    // MARK: Device flow

    @Test func deviceFlowWaitsThenReturnsTheToken() async throws {
        #expect(!OAuthDeviceFlow.isAvailable(for: .bitbucket))
        if !OAuthDeviceFlow.isAvailable(for: .github) {
            await #expect(throws: HostingError.self) {
                _ = try await OAuthDeviceFlow.start(.github, host: "github.com", http: FakeHTTPClient { _ in (200, "{}") })
            }
        }
        let responses = LockedQueue([#"{"error":"authorization_pending"}"#, #"{"access_token":"gho_new"}"#])
        let http = FakeHTTPClient { request in
            request.url?.path == "/login/device/code"
                ? (200, #"{"device_code":"d","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","interval":5}"#)
                : (200, responses.next())
        }
        let code = try await OAuthDeviceFlow.start(.github, host: "github.com", http: http, clientID: "test-client")
        #expect(code.userCode == "ABCD-1234")
        #expect(try await OAuthDeviceFlow.poll(.github, host: "github.com", code: code, http: http, clientID: "test-client") == .pending)
        #expect(try await OAuthDeviceFlow.poll(.github, host: "github.com", code: code, http: http, clientID: "test-client")
                == .token("gho_new"))
        let body = String(bytes: http.requests.last?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("client_id=test-client") && body.contains("device_code=d"))
    }

    // MARK: Keychain

    @Test func keychainRoundTripUnderATestOnlyService() {
        let store = KeychainSecretStore(service: "Grove Tests \(UUID().uuidString)")
        let id = UUID()
        defer { store.setSecret(nil, for: id) }
        store.setSecret("secret-1", for: id)
        #expect(store.secret(for: id) == "secret-1")
        store.setSecret("secret-2", for: id)
        #expect(store.secret(for: id) == "secret-2")
        store.setSecret(nil, for: id)
        #expect(store.secret(for: id) == nil)
    }
}

private final class LockedQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String]
    init(_ items: [String]) { self.items = items }
    func next() -> String { lock.withLock { items.isEmpty ? "{}" : items.removeFirst() } }
}
