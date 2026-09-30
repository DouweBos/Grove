// HostingServiceTests.swift
// GroveTests

import Foundation
import Testing
@testable import Grove

/// Answers requests from a closure and records them, so write paths are checked without a network.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let respond: @Sendable (URLRequest) -> (Int, String)

    init(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) { self.respond = respond }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let (status, body) = respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    func secret(for account: UUID) -> String? { lock.withLock { values[account] } }
    func setSecret(_ secret: String?, for account: UUID) { lock.withLock { values[account] = secret } }
}

@MainActor
func makeAccountStore() -> HostingAccountStore {
    let suite = "grove-tests-\(UUID().uuidString)"
    return HostingAccountStore(defaults: UserDefaults(suiteName: suite)!, secrets: MemorySecretStore())
}

@MainActor
struct HostingServiceTests {

    // MARK: Detection

    @Test func parsesEachServicesURLs() {
        let github = RemoteLocation.parse("git@github.com:DouweBos/Grove.git")
        #expect(github?.kind == .github && github?.fullName == "DouweBos/Grove")
        #expect(RemoteLocation.parse("https://DouweBos@github.com/DouweBos/Grove")?.name == "Grove")

        let gitlab = RemoteLocation.parse("https://gitlab.com/group/sub/project.git")
        #expect(gitlab?.kind == .gitlab && gitlab?.owner == "group/sub" && gitlab?.name == "project")
        #expect(RemoteLocation.parse("ssh://git@gitlab.example.com:2222/team/app.git")?.host == "gitlab.example.com")

        let bitbucket = RemoteLocation.parse("git@bitbucket.org:workspace/repo.git")
        #expect(bitbucket?.kind == .bitbucket && bitbucket?.owner == "workspace")

        let azure = RemoteLocation.parse("https://org@dev.azure.com/org/My%20Project/_git/repo")
        #expect(azure?.kind == .azureDevOps && azure?.owner == "org" && azure?.project == "My%20Project" && azure?.name == "repo")
        let azureSSH = RemoteLocation.parse("git@ssh.dev.azure.com:v3/org/project/repo")
        #expect(azureSSH?.owner == "org" && azureSSH?.project == "project" && azureSSH?.name == "repo")
        let legacy = RemoteLocation.parse("https://org.visualstudio.com/project/_git/repo")
        #expect(legacy?.owner == "org" && legacy?.project == "project")
    }

    @Test func ignoresLocalAndUnknownRemotes() {
        #expect(RemoteLocation.parse("/tmp/remote.git") == nil)
        #expect(RemoteLocation.parse("file:///tmp/remote.git") == nil)
        #expect(RemoteLocation.parse("https://example.com/a/b.git") == nil)
    }

    // MARK: Resolving

    private func remote(_ url: String, name: String = "origin") -> RemoteInfo {
        RemoteInfo(id: name, name: name, url: url, pushURL: nil)
    }

    @Test func serviceWithoutAccountAsksForOne() {
        let store = makeAccountStore()
        #expect(throws: HostingError.noAccount(.github, host: "github.com")) {
            _ = try PullRequestHostResolver.resolve(remotes: [remote("git@github.com:o/r.git")], accounts: store)
        }
        #expect(throws: HostingError.noAccount(.bitbucket, host: "bitbucket.org")) {
            _ = try PullRequestHostResolver.resolve(remotes: [remote("git@bitbucket.org:w/r.git")], accounts: store)
        }
        #expect(throws: HostingError.noHostedRemote) {
            _ = try PullRequestHostResolver.resolve(remotes: [remote("/tmp/x.git")], accounts: store)
        }
    }

    @Test func accountsServeOnlyTheirOrganization() throws {
        let store = makeAccountStore()
        store.add(HostingAccount(kind: .azureDevOps, username: "me", organization: "contoso"), secret: "pat")
        let resolved = try PullRequestHostResolver.resolve(
            remotes: [remote("/tmp/local", name: "backup"), remote("https://dev.azure.com/contoso/p/_git/r", name: "upstream")],
            accounts: store)
        #expect(resolved.host.kind == .azureDevOps && resolved.remote == "upstream")
        #expect(throws: HostingError.noAccount(.azureDevOps, host: "dev.azure.com/fabrikam")) {
            _ = try PullRequestHostResolver.resolve(remotes: [remote("https://dev.azure.com/fabrikam/p/_git/r")], accounts: store)
        }
    }

    @Test func removingAnAccountDropsItsSecret() {
        let store = makeAccountStore()
        let account = HostingAccount(kind: .bitbucket, username: "me")
        store.add(account, secret: "app-password")
        #expect(store.secret(for: account) == "app-password")
        store.remove(account)
        #expect(store.accounts.isEmpty && store.secret(for: account) == nil)
    }

    @Test func credentialsUseEachServicesBasicAuth() {
        let github = RESTCredentials(account: HostingAccount(kind: .github, username: "me"), secret: "tok")
        #expect(github.authorizationHeader == "Bearer tok")
        let bitbucket = RESTCredentials(account: HostingAccount(kind: .bitbucket, username: "me"), secret: "pw")
        #expect(bitbucket.authorizationHeader == "Basic " + Data("me:pw".utf8).base64EncodedString())
        let azure = RESTCredentials(account: HostingAccount(kind: .azureDevOps, username: "me", organization: "o"), secret: "pat")
        #expect(azure.authorizationHeader == "Basic " + Data(":pat".utf8).base64EncodedString())
    }

    // MARK: Failures

    @Test func loadFailuresNameTheFix() {
        #expect(HostLoadFailure(HostingError.noAccount(.bitbucket, host: "bitbucket.org")) == .noAccount(.bitbucket, host: "bitbucket.org"))
        #expect(HostLoadFailure(HostingError.notSignedIn(.gitlab)) == .notSignedIn(.gitlab))
        #expect(HostLoadFailure(HostingError.noHostedRemote) == .noHostedRemote)
        #expect(HostLoadFailure(HostingError.http(status: 403, message: "Resource not accessible")) == .forbidden("Resource not accessible"))
        #expect(HostLoadFailure(HostingError.http(status: 404, message: "")) == .other("The server answered 404."))
    }

    @Test func featuresUseTheServicesOwnNoun() {
        #expect(HostFeature.pullRequests.noun(on: .gitlab) == "merge requests")
        #expect(HostFeature.pullRequests.noun(on: nil) == "pull requests")
    }

    @Test func concatenatedPagesAndLinesAllParse() {
        #expect(HostingJSON.objects(#"[{"a":1}][{"a":2},{"a":"]["}]"#).count == 3)
        #expect(HostingJSON.objects("{\"a\":1}\n{\"a\":2}").count == 2)
        #expect(HostingJSON.objects("").isEmpty)
    }

    // MARK: Accounts

    @Test func addingVerifiesTheTokenFirst() async {
        let refused = FakeHTTPClient { _ in (401, "") }
        let viewModel = AccountsViewModel(store: makeAccountStore(), http: refused)
        viewModel.cliLogins = { [] }
        viewModel.beginAdding(.bitbucket)
        viewModel.updateForm { $0.username = "me"; $0.token = "bad" }
        await viewModel.submitForm()
        #expect(viewModel.accounts.isEmpty)
        #expect(viewModel.form?.error != nil)
        #expect(refused.requests.first?.url?.absoluteString == "https://api.bitbucket.org/2.0/user")
        #expect(refused.requests.first?.httpMethod == "GET")

        let accepted = FakeHTTPClient { _ in (200, "{}") }
        let second = AccountsViewModel(store: makeAccountStore(), http: accepted)
        second.beginAdding(.azureDevOps)
        second.updateForm { $0.organization = "contoso"; $0.token = "pat" }
        await second.submitForm()
        #expect(second.form == nil)
        #expect(second.accounts.first?.organization == "contoso")
        #expect(accepted.requests.first?.url?.host == "dev.azure.com")
    }
}
