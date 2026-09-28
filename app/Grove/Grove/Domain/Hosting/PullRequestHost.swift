// Domain/Hosting/PullRequestHost.swift
// Grove
//
// One service's pull request API, reached over HTTPS with the account's token.

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
    /// A ref the remote keeps for the pull request's head (`refs/pull/N/head`), which also covers forks;
    /// nil where there is none and the source branch is fetched instead.
    func headRef(number: Int) -> String?
}

extension PullRequestHost {
    func headRef(number: Int) -> String? { nil }
}

/// Why a repository's pull requests can't be reached.
nonisolated enum HostingError: LocalizedError, Equatable {
    /// No remote points at a service Grove knows.
    case noHostedRemote
    /// The service needs an account in Preferences > Accounts.
    case noAccount(HostingServiceKind, host: String)
    /// The stored token was refused.
    case notSignedIn(HostingServiceKind)
    case unsupported(String)
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noHostedRemote: "None of this repository's remotes point at GitHub, GitLab, Bitbucket or Azure DevOps."
        case .noAccount(let kind, let host): "Add a \(kind.displayName) account for \(host) in Settings > Accounts."
        case .notSignedIn(let kind): "\(kind.displayName) refused the sign-in. Sign in again in Settings > Accounts."
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

/// Authenticated JSON requests against one service's API.
nonisolated struct RESTClient: Sendable {
    let credentials: RESTCredentials
    var http: any HTTPClient = URLSessionHTTPClient()

    func get(_ url: URL, accept: String = "application/json") async throws -> Data {
        try await send("GET", url, body: nil, accept: accept).data
    }

    /// Every page of a list, following `Link: <…>; rel="next"` (GitHub, GitLab) up to `maxPages`.
    func getPages(_ url: URL, maxPages: Int = 10) async throws -> [HostingJSON.Object] {
        var objects: [HostingJSON.Object] = []
        var next: URL? = url
        var pages = 0
        while let page = next, pages < maxPages {
            let (data, response) = try await send("GET", page, body: nil, accept: "application/json")
            objects += HostingJSON.objects(String(bytes: data, encoding: .utf8) ?? "")
            next = Self.nextPage(response.value(forHTTPHeaderField: "Link"))
            pages += 1
        }
        return objects
    }

    @discardableResult
    func send(_ method: String, _ url: URL, json: [String: Any]?) async throws -> Data {
        try await send(method, url, body: json.map { try JSONSerialization.data(withJSONObject: $0) }, accept: "application/json").data
    }

    /// A GraphQL query (a POST that only reads); GraphQL reports errors in the body with a 200.
    func graphQL(_ url: URL, query: String, variables: [String: Any]) async throws -> HostingJSON.Object {
        let data = try await send("POST", url, json: ["query": query, "variables": variables])
        let object = HostingJSON.object(data) ?? [:]
        if let errors = object["errors"] as? [HostingJSON.Object], let first = errors.first?["message"] as? String {
            throw HostingError.unsupported(first)
        }
        return object["data"] as? HostingJSON.Object ?? [:]
    }

    private func send(_ method: String, _ url: URL, body: Data?, accept: String) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if credentials.account.kind == .github { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await http.data(for: request)
        switch response.statusCode {
        // Azure DevOps answers a bad PAT with a 203 and its sign-in page.
        case 203 where credentials.account.kind == .azureDevOps, 401:
            throw HostingError.notSignedIn(credentials.account.kind)
        case 200..<300: return (data, response)
        default: throw HostingError.http(status: response.statusCode, message: Self.message(in: data))
        }
    }

    /// `<https://…?page=2>; rel="next", <…>; rel="last"` → the next page.
    static func nextPage(_ link: String?) -> URL? {
        guard let link else { return nil }
        for part in link.split(separator: ",") where part.contains("rel=\"next\"") {
            guard let open = part.firstIndex(of: "<"), let close = part.firstIndex(of: ">"), open < close else { continue }
            return URL(string: String(part[part.index(after: open)..<close]))
        }
        return nil
    }

    /// The human part of an error body: GitHub's and Azure's `message`, Bitbucket's `error.message`, GitLab's `message`/`error`.
    static func message(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(bytes: data.prefix(300), encoding: .utf8) ?? ""
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = object["message"] as? String {
            let details = (object["errors"] as? [[String: Any]])?.compactMap { $0["message"] as? String } ?? []
            return ([message] + details).joined(separator: " ")
        }
        if let messages = object["message"] as? [String] { return messages.joined(separator: " ") }
        return object["error"] as? String ?? ""
    }
}

// MARK: - Resolving

@MainActor
enum PullRequestHostResolver {

    /// The host behind the first remote Grove recognizes (origin first), and that remote's name.
    static func resolve(remotes: [RemoteInfo], accounts: HostingAccountStore? = nil,
                        http: any HTTPClient = URLSessionHTTPClient()) throws -> (host: any PullRequestHost, remote: String) {
        let ordered = remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
        guard let (remote, location) = ordered.lazy.compactMap({ remote in RemoteLocation.parse(remote.url).map { (remote.name, $0) } })
            .first else { throw HostingError.noHostedRemote }
        return (try host(for: location, accounts: accounts ?? .shared, http: http), remote)
    }

    /// The service of the remote `resolve` would use, without needing an account for it.
    static func service(of remotes: [RemoteInfo]) -> HostingServiceKind? {
        let ordered = remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
        return ordered.lazy.compactMap { RemoteLocation.parse($0.url)?.kind }.first
    }

    static func host(for location: RemoteLocation, accounts: HostingAccountStore, http: any HTTPClient) throws -> any PullRequestHost {
        guard let credentials = accounts.credentials(for: location) else {
            let host = location.kind == .azureDevOps ? "\(location.host)/\(location.owner)" : location.host
            throw HostingError.noAccount(location.kind, host: host)
        }
        let client = RESTClient(credentials: credentials, http: http)
        switch location.kind {
        case .github: return GitHubPullRequestHost(location: location, client: client)
        case .gitlab: return GitLabPullRequestHost(location: location, client: client)
        case .bitbucket: return BitbucketPullRequestHost(location: location, client: client)
        case .azureDevOps: return AzureDevOpsPullRequestHost(location: location, client: client)
        }
    }
}
