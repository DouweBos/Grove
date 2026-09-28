// Domain/Hosting/AccountSignIn.swift
// Grove
//
// Signing in: which services the Accounts tab offers, the token check, OAuth device flow and importing CLI logins.

import Foundation

/// What "Add Account" offers; GitHub Enterprise and self-hosted GitLab are their service on another host.
nonisolated enum AccountProvider: String, CaseIterable, Identifiable, Sendable {
    case github, githubEnterprise, gitlab, gitlabSelfHosted, bitbucket, azureDevOps

    var id: String { rawValue }

    var kind: HostingServiceKind {
        switch self {
        case .github, .githubEnterprise: .github
        case .gitlab, .gitlabSelfHosted: .gitlab
        case .bitbucket: .bitbucket
        case .azureDevOps: .azureDevOps
        }
    }

    var title: String {
        switch self {
        case .github: "GitHub"
        case .githubEnterprise: "GitHub Enterprise"
        case .gitlab: "GitLab"
        case .gitlabSelfHosted: "Self-Hosted GitLab"
        case .bitbucket: "Bitbucket Cloud"
        case .azureDevOps: "Azure DevOps"
        }
    }

    /// Enterprise and self-hosted providers ask for the host.
    var asksForHost: Bool { self == .githubEnterprise || self == .gitlabSelfHosted }

    /// Bitbucket's app passwords are tied to a username the token can't tell us.
    var asksForUsername: Bool { self == .bitbucket }

    static func matching(_ account: HostingAccount) -> AccountProvider {
        switch account.kind {
        case .github: account.host == "github.com" ? .github : .githubEnterprise
        case .gitlab: account.host == "gitlab.com" ? .gitlab : .gitlabSelfHosted
        case .bitbucket: .bitbucket
        case .azureDevOps: .azureDevOps
        }
    }

    /// Where the user creates a token, and what it needs.
    func tokenPage(host: String, organization: String) -> URL? {
        switch self {
        case .github, .githubEnterprise:
            URL(string: "https://\(host)/settings/tokens/new?scopes=repo,read:org,workflow&description=Grove")
        case .gitlab, .gitlabSelfHosted:
            URL(string: "https://\(host)/-/user_settings/personal_access_tokens?name=Grove&scopes=api,read_user")
        case .bitbucket:
            URL(string: "https://bitbucket.org/account/settings/app-passwords/")
        case .azureDevOps:
            URL(string: "https://dev.azure.com/\(organization.isEmpty ? "" : organization + "/")_usersSettings/tokens")
        }
    }

    var scopes: String {
        switch self {
        case .github, .githubEnterprise: "repo, read:org (and workflow to push workflow files)"
        case .gitlab, .gitlabSelfHosted: "api, read_user"
        case .bitbucket: "Account: Read, Repositories: Read & Write, Pull requests: Read & Write"
        case .azureDevOps: "Code: Read & Write, Project and Team: Read"
        }
    }
}

// MARK: - API locations

extension HostingAccount {
    /// Root of the service's REST API for this account.
    nonisolated var apiBase: String {
        switch kind {
        case .github: host == "github.com" ? "https://api.github.com" : "https://\(host)/api/v3"
        case .gitlab: "https://\(host)/api/v4"
        case .bitbucket: "https://api.bitbucket.org/2.0"
        case .azureDevOps: "https://dev.azure.com/\(organization ?? "")"
        }
    }

    nonisolated var graphQLURL: URL? {
        URL(string: host == "github.com" ? "https://api.github.com/graphql" : "https://\(host)/api/graphql")
    }
}

// MARK: - Checking a token

nonisolated enum HostingAccountVerifier {

    /// A read-only "who am I" the token must be allowed to make; Azure DevOps lists one of the organization's projects.
    static func verificationURL(for account: HostingAccount) -> URL? {
        switch account.kind {
        case .github, .gitlab, .bitbucket: URL(string: "\(account.apiBase)/user")
        case .azureDevOps: URL(string: "\(account.apiBase)/_apis/projects?$top=1&api-version=7.1")
        }
    }

    /// Checks the token and returns the login it belongs to (for Azure DevOps, the name given, else the organization).
    static func whoAmI(_ credentials: RESTCredentials, http: any HTTPClient) async throws -> String {
        guard let url = verificationURL(for: credentials.account) else { throw HostingError.unsupported("Bad host.") }
        let data = try await RESTClient(credentials: credentials, http: http).get(url)
        let object = HostingJSON.object(data) ?? [:]
        switch credentials.account.kind {
        case .github: return object["login"] as? String ?? credentials.account.username
        case .gitlab: return object["username"] as? String ?? credentials.account.username
        case .bitbucket: return object["username"] as? String ?? object["nickname"] as? String ?? credentials.account.username
        case .azureDevOps:
            let name = credentials.account.username
            return name.isEmpty ? credentials.account.organization ?? "" : name
        }
    }
}

// MARK: - OAuth device flow

/// GitHub's and GitLab's device authorization: show a code, the user approves it in the browser, Grove polls for the token.
nonisolated enum OAuthDeviceFlow {

    // TODO: Register a Grove OAuth app (device flow enabled) and put its client id here; until then tokens are entered by hand.
    /// Grove's registered OAuth app on github.com.
    static let githubClientID = ""
    // TODO: Register a Grove application on gitlab.com with the device grant and put its id here.
    /// Grove's OAuth application on gitlab.com (self-hosted GitLab needs its own).
    static let gitlabClientID = ""

    struct Code: Equatable, Sendable {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let interval: Int
    }

    enum Poll: Equatable, Sendable {
        case pending
        case slowDown
        case token(String)
    }

    static func clientID(for provider: AccountProvider) -> String? {
        let id: String = switch provider {
        case .github: githubClientID
        case .gitlab: gitlabClientID
        default: ""
        }
        return id.isEmpty ? nil : id
    }

    static func isAvailable(for provider: AccountProvider) -> Bool { clientID(for: provider) != nil }

    private static func endpoints(_ provider: AccountProvider, host: String) -> (code: URL, token: URL)? {
        switch provider {
        case .github:
            guard let code = URL(string: "https://\(host)/login/device/code"),
                  let token = URL(string: "https://\(host)/login/oauth/access_token") else { return nil }
            return (code, token)
        case .gitlab:
            guard let code = URL(string: "https://\(host)/oauth/authorize_device"),
                  let token = URL(string: "https://\(host)/oauth/token") else { return nil }
            return (code, token)
        default:
            return nil
        }
    }

    private static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return request
    }

    /// `clientID` stands in for the registered one, for tests.
    static func start(_ provider: AccountProvider, host: String, http: any HTTPClient, clientID: String? = nil) async throws -> Code {
        guard let clientID = clientID ?? self.clientID(for: provider), let urls = endpoints(provider, host: host) else {
            throw HostingError.unsupported("Browser sign-in isn't set up for \(provider.title); use a token instead.")
        }
        let scope = provider.kind == .github ? "repo read:org workflow" : "api read_user"
        let (data, response) = try await http.data(for: form(urls.code, ["client_id": clientID, "scope": scope]))
        let object = HostingJSON.object(data) ?? [:]
        guard response.statusCode == 200, let deviceCode = object["device_code"] as? String, let userCode = object["user_code"] as? String,
              let uri = (object["verification_uri_complete"] ?? object["verification_uri"]) as? String, let url = URL(string: uri) else {
            throw HostingError.http(status: response.statusCode, message: RESTClient.message(in: data))
        }
        return Code(deviceCode: deviceCode, userCode: userCode, verificationURL: url, interval: object["interval"] as? Int ?? 5)
    }

    static func poll(_ provider: AccountProvider, host: String, code: Code, http: any HTTPClient,
                     clientID: String? = nil) async throws -> Poll {
        guard let clientID = clientID ?? self.clientID(for: provider), let urls = endpoints(provider, host: host) else { return .pending }
        let fields = ["client_id": clientID, "device_code": code.deviceCode,
                      "grant_type": "urn:ietf:params:oauth:grant-type:device_code"]
        let (data, _) = try await http.data(for: form(urls.token, fields))
        let object = HostingJSON.object(data) ?? [:]
        if let token = object["access_token"] as? String { return .token(token) }
        switch object["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        default: throw HostingError.unsupported(object["error_description"] as? String ?? "Sign-in was declined or expired.")
        }
    }
}

// MARK: - Importing CLI logins

/// Reads tokens the GitHub and GitLab CLIs already hold, without changing their configuration.
nonisolated enum CLITokenImport {

    struct Found: Equatable, Sendable {
        let kind: HostingServiceKind
        let host: String
        let token: String
    }

    static var ghPath: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var glabPath: String? {
        ["/opt/homebrew/bin/glab", "/usr/local/bin/glab", "/usr/bin/glab"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The user's real home, even when Foundation's is redirected for a test run.
    private static var home: String {
        ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    private static func run(_ executable: String, _ arguments: [String]) async -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["GH_PROMPT_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        process.environment = env
        guard let result = try? await ProcessRunner.run(process) else { return (-1, "") }
        let text = (String(bytes: result.stdout, encoding: .utf8) ?? "") + (String(bytes: result.stderr, encoding: .utf8) ?? "")
        return (result.status, text)
    }

    /// Every host `gh auth status` lists, with `gh auth token --hostname` for each.
    static func githubLogins() async -> [Found] {
        guard let gh = ghPath else { return [] }
        let hosts = parseGitHubHosts(await run(gh, ["auth", "status"]).output)
        var found: [Found] = []
        for host in hosts {
            let result = await run(gh, ["auth", "token", "--hostname", host])
            let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.status == 0, !token.isEmpty, !token.contains(" ") { found.append(Found(kind: .github, host: host, token: token)) }
        }
        return found
    }

    /// Host lines of `gh auth status` are the unindented ones, e.g. `github.com`.
    static func parseGitHubHosts(_ status: String) -> [String] {
        status.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !raw.hasPrefix(" ") && !line.contains(" ") && line.contains(".") ? line : nil
        }
    }

    /// Tokens in glab's `config.yml`; logins kept in the system keyring aren't readable this way.
    static func gitlabLogins() -> [Found] {
        let candidates = [ProcessInfo.processInfo.environment["GLAB_CONFIG_DIR"].map { "\($0)/config.yml" },
                          "\(home)/.config/glab-cli/config.yml",
                          "\(home)/Library/Application Support/glab-cli/config.yml"].compactMap { $0 }
        for path in candidates {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) { return parseGitLabConfig(text) }
        }
        return []
    }

    /// The `hosts:` map of glab's YAML config: two-space host keys, each with a `token:` below it.
    static func parseGitLabConfig(_ yaml: String) -> [Found] {
        var found: [Found] = []
        var inHosts = false
        var host: String?
        for raw in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 0 { inHosts = trimmed == "hosts:"; host = nil; continue }
            guard inHosts, !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if indent == 2, trimmed.hasSuffix(":") {
                host = String(trimmed.dropLast())
            } else if let current = host, trimmed.hasPrefix("token:") {
                let value = trimmed.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty, !value.hasPrefix("!!") { found.append(Found(kind: .gitlab, host: current, token: value)) }
            }
        }
        return found
    }
}
