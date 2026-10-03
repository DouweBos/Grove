// Domain/Hosting/PullRequestHost.swift
// Grove
//
// One service's pull request API, reached over HTTPS with the account's token.

import Foundation
import GroveKit

// MARK: - HTTP

nonisolated protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Like `data(for:)`, but a redirect comes back as the 3xx response instead of being followed.
    func dataWithoutRedirect(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Saves a successful response's body at `destination`, replacing what's there, without holding it in memory.
    func download(for request: URLRequest, to destination: URL) async throws -> HTTPURLResponse
}

extension HTTPClient {
    func dataWithoutRedirect(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await data(for: request)
    }

    func download(for request: URLRequest, to destination: URL) async throws -> HTTPURLResponse {
        let (data, response) = try await data(for: request)
        if (200..<300).contains(response.statusCode) { try data.write(to: destination, options: .atomic) }
        return response
    }
}

nonisolated struct URLSessionHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Self.http(try await URLSession.shared.data(for: request))
    }

    func dataWithoutRedirect(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Self.http(try await URLSession.shared.data(for: request, delegate: RedirectStopper()))
    }

    func download(for request: URLRequest, to destination: URL) async throws -> HTTPURLResponse {
        let (file, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse else { throw HostingError.http(status: 0, message: "No HTTP response.") }
        if (200..<300).contains(http.statusCode) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: file)
        }
        return http
    }

    private static func http(_ result: (Data, URLResponse)) throws -> (Data, HTTPURLResponse) {
        guard let http = result.1 as? HTTPURLResponse else { throw HostingError.http(status: 0, message: "No HTTP response.") }
        return (result.0, http)
    }
}

/// Answers a redirect with "don't", so the task finishes with the 3xx response.
private nonisolated final class RedirectStopper: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Authenticated JSON requests against one service's API.
nonisolated struct RESTClient: Sendable {
    let credentials: RESTCredentials
    var http: any HTTPClient = URLSessionHTTPClient()

    func get(_ url: URL, accept: String = "application/json",
             cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> Data {
        try await send("GET", url, body: nil, accept: accept, cachePolicy: cachePolicy).data
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
            // A token without a scope the query needs is a 403 in REST terms; GraphQL says so in the body.
            if errors.first?["type"] as? String == "INSUFFICIENT_SCOPES" { throw HostingError.http(status: 403, message: first) }
            throw HostingError.unsupported(first)
        }
        return object["data"] as? HostingJSON.Object ?? [:]
    }

    func send(_ method: String, _ url: URL, body: Data?, accept: String,
              cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = authorized(method, url, accept: accept)
        request.cachePolicy = cachePolicy
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await http.data(for: request)
        try check(response, data)
        return (data, response)
    }

    /// Throws unless the response is a success.
    func check(_ response: HTTPURLResponse, _ data: Data) throws {
        switch response.statusCode {
        // Azure DevOps answers a bad PAT with a 203 and its sign-in page.
        case 203 where credentials.account.kind == .azureDevOps, 401:
            throw HostingError.notSignedIn(credentials.account.kind)
        case 200..<300: return
        default: throw HostingError.http(status: response.statusCode, message: Self.message(in: data))
        }
    }

    func authorized(_ method: String, _ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if credentials.account.kind == .github { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
        return request
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

/// The remote a repository's host features talk to, and an API client for it.
@MainActor
enum HostedRemoteResolver {

    /// The first remote Grove recognizes, origin first.
    static func location(of remotes: [RemoteInfo]) -> (remote: String, location: RemoteLocation)? {
        let ordered = remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
        return ordered.lazy.compactMap { remote in RemoteLocation.parse(remote.url).map { (remote.name, $0) } }.first
    }

    /// A client signed in with the account that serves `location`.
    static func client(for location: RemoteLocation, accounts: HostingAccountStore, http: any HTTPClient) throws -> RESTClient {
        guard let credentials = accounts.credentials(for: location) else {
            let host = location.kind == .azureDevOps ? "\(location.host)/\(location.owner)" : location.host
            throw HostingError.noAccount(location.kind, host: host)
        }
        return RESTClient(credentials: credentials, http: http)
    }
}

@MainActor
enum PullRequestHostResolver {

    /// The host behind the first remote Grove recognizes (origin first), and that remote's name.
    static func resolve(remotes: [RemoteInfo], accounts: HostingAccountStore? = nil,
                        http: any HTTPClient = URLSessionHTTPClient()) throws -> (host: any PullRequestHost, remote: String) {
        guard let (remote, location) = HostedRemoteResolver.location(of: remotes) else { throw HostingError.noHostedRemote }
        return (try host(for: location, accounts: accounts ?? .shared, http: http), remote)
    }

    /// The service of the remote `resolve` would use, without needing an account for it.
    static func service(of remotes: [RemoteInfo]) -> HostingServiceKind? {
        HostedRemoteResolver.location(of: remotes)?.location.kind
    }

    static func host(for location: RemoteLocation, accounts: HostingAccountStore, http: any HTTPClient) throws -> any PullRequestHost {
        let client = try HostedRemoteResolver.client(for: location, accounts: accounts, http: http)
        switch location.kind {
        case .github: return GitHubPullRequestHost(location: location, client: client)
        case .gitlab: return GitLabPullRequestHost(location: location, client: client)
        case .bitbucket: return BitbucketPullRequestHost(location: location, client: client)
        case .azureDevOps: return AzureDevOpsPullRequestHost(location: location, client: client)
        }
    }
}
