// Domain/Hosting/PullRequestHost.swift
// Grove
//
// One service's pull request API, whichever way it's reached: gh, glab or REST.

import Foundation

/// Pull requests of one repository on its hosting service.
nonisolated protocol PullRequestHost: Sendable {
    var kind: HostingServiceKind { get }
    func pullRequests() async throws -> [PullRequestInfo]
    func openPullRequests() async throws -> [String: OpenPullRequest]
    func pullRequest(number: Int) async throws -> PullRequestInfo
    func comments(number: Int) async throws -> [PRComment]
    func reviewComments(number: Int) async throws -> [PRReviewComment]
    func commits(number: Int) async throws -> [CommitInfo]
    /// Unified diff of the pull request; nil when the service has none, so the branches are diffed locally.
    func diff(number: Int) async throws -> String?
    func merge(number: Int) async throws
    func close(number: Int) async throws
    func comment(number: Int, body: String) async throws
    /// Opens a pull request and returns its web URL.
    func create(_ draft: PullRequestDraft) async throws -> String
    func webURL(number: Int) async throws -> URL?
    /// Checks out through the service's CLI; false leaves it to a plain fetch and checkout of the source branch.
    func checkout(number: Int) async throws -> Bool
}

/// Why a repository's pull requests can't be reached.
nonisolated enum HostingError: LocalizedError, Equatable {
    /// No remote points at a service Grove knows.
    case noHostedRemote
    /// The service needs an account in Preferences > Accounts.
    case noAccount(HostingServiceKind, host: String)
    /// The service's command-line tool isn't installed.
    case cliMissing(HostingServiceKind)
    /// The CLI is installed but signed out, or the stored token was refused.
    case notSignedIn(HostingServiceKind)
    case unsupported(String)
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noHostedRemote: "None of this repository's remotes point at GitHub, GitLab, Bitbucket or Azure DevOps."
        case .noAccount(let kind, let host): "Add a \(kind.displayName) account for \(host) in Settings > Accounts."
        case .cliMissing(let kind): "\(kind.displayName) needs its command-line tool (\(kind == .gitlab ? "glab" : "gh"))."
        case .notSignedIn(let kind): "\(kind.displayName) refused the sign-in. Check the account in Settings > Accounts."
        case .unsupported(let message): message
        case .http(let status, let message): message.isEmpty ? "The server answered \(status)." : message
        }
    }
}

// MARK: - HTTP

nonisolated protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HostingError.http(status: 0, message: "No HTTP response.") }
        return (data, http)
    }
}

/// Authenticated JSON requests against one service's REST API.
nonisolated struct RESTClient: Sendable {
    let credentials: RESTCredentials
    var http: any HTTPClient = URLSessionHTTPClient()

    func get(_ url: URL, accept: String = "application/json") async throws -> Data {
        try await send("GET", url, body: nil, accept: accept)
    }

    func send(_ method: String, _ url: URL, json: [String: Any]?) async throws -> Data {
        try await send(method, url, body: json.map { try JSONSerialization.data(withJSONObject: $0) }, accept: "application/json")
    }

    private func send(_ method: String, _ url: URL, body: Data?, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await http.data(for: request)
        switch response.statusCode {
        // Azure DevOps answers a bad PAT with a 203 and its sign-in page.
        case 203 where credentials.account.kind == .azureDevOps, 401, 403:
            throw HostingError.notSignedIn(credentials.account.kind)
        case 200..<300: return data
        default: throw HostingError.http(status: response.statusCode, message: Self.message(in: data))
        }
    }

    /// The human part of an error body: Bitbucket's `error.message`, Azure's `message`.
    static func message(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(bytes: data.prefix(300), encoding: .utf8) ?? ""
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return object["message"] as? String ?? ""
    }
}

// MARK: - Resolving

@MainActor
enum PullRequestHostResolver {

    /// The host behind the first remote Grove recognizes (origin first), and that remote's name.
    static func resolve(remotes: [RemoteInfo], directory: URL, accounts: HostingAccountStore? = nil,
                        http: any HTTPClient = URLSessionHTTPClient()) throws -> (host: any PullRequestHost, remote: String) {
        let ordered = remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
        guard let (remote, location) = ordered.lazy.compactMap({ remote in RemoteLocation.parse(remote.url).map { (remote.name, $0) } })
            .first else { throw HostingError.noHostedRemote }
        return (try host(for: location, directory: directory, accounts: accounts ?? .shared, http: http), remote)
    }

    /// The service of the remote `resolve` would use, without needing an account for it.
    static func service(of remotes: [RemoteInfo]) -> HostingServiceKind? {
        let ordered = remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
        return ordered.lazy.compactMap { RemoteLocation.parse($0.url)?.kind }.first
    }

    static func host(for location: RemoteLocation, directory: URL, accounts: HostingAccountStore,
                     http: any HTTPClient) throws -> any PullRequestHost {
        switch location.kind {
        case .github:
            guard GitHubCLI.isInstalled else { throw HostingError.cliMissing(.github) }
            return GitHubPullRequestHost(directory: directory)
        case .gitlab:
            guard GitLabCLI.isInstalled else { throw HostingError.cliMissing(.gitlab) }
            return GitLabPullRequestHost(directory: directory, location: location)
        case .bitbucket:
            guard let credentials = accounts.credentials(for: location) else {
                throw HostingError.noAccount(.bitbucket, host: location.host)
            }
            return BitbucketPullRequestHost(location: location, client: RESTClient(credentials: credentials, http: http))
        case .azureDevOps:
            guard let credentials = accounts.credentials(for: location) else {
                throw HostingError.noAccount(.azureDevOps, host: "\(location.host)/\(location.owner)")
            }
            return AzureDevOpsPullRequestHost(location: location, client: RESTClient(credentials: credentials, http: http))
        }
    }
}
