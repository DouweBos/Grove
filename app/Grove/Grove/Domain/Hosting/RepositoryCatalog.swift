// Domain/Hosting/RepositoryCatalog.swift
// Grove
//
// The repositories one signed-in account can see, for the cloud browser.

import Foundation

/// One signed-in account in the cloud browser.
nonisolated struct CatalogAccount: Identifiable, Hashable, Sendable {
    let id: String
    let kind: HostingServiceKind
    let host: String
    /// Login, email or organization, whatever the service knows the account by.
    let title: String
}

/// Owners (the account, its organizations, groups, workspaces or projects) and their repositories.
nonisolated protocol RepositoryCatalog: Sendable {
    var account: CatalogAccount { get }
    func owners() async throws -> [RemoteRepositoryOwner]
    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository]
    /// Creates an empty repository under `request.owner` and returns it.
    func createRepository(_ request: NewRemoteRepository) async throws -> RemoteRepository
    /// Azure DevOps sets visibility per project and has no repository description.
    var supportsVisibilityAndDescription: Bool { get }
}

extension RepositoryCatalog {
    var supportsVisibilityAndDescription: Bool { true }
}

@MainActor
enum RepositoryCatalogs {

    /// A catalog for every account in Settings > Accounts that has a token.
    static func all(accounts: HostingAccountStore? = nil, http: any HTTPClient = URLSessionHTTPClient()) async -> [any RepositoryCatalog] {
        let store = accounts ?? .shared
        return store.accounts.compactMap { account -> (any RepositoryCatalog)? in
            guard let credentials = store.credentials(for: account) else { return nil }
            let client = RESTClient(credentials: credentials, http: http)
            switch account.kind {
            case .github: return GitHubCatalog(hostingAccount: account, client: client)
            case .gitlab: return GitLabCatalog(hostingAccount: account, client: client)
            case .bitbucket: return BitbucketCatalog(hostingAccount: account, client: client)
            case .azureDevOps: return AzureDevOpsCatalog(hostingAccount: account, client: client)
            }
        }
    }
}

// MARK: - GitHub

nonisolated struct GitHubCatalog: RepositoryCatalog {
    let hostingAccount: HostingAccount
    let client: RESTClient
    var account: CatalogAccount {
        CatalogAccount(id: "github:\(hostingAccount.id)", kind: .github, host: hostingAccount.host, title: hostingAccount.title)
    }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: hostingAccount.apiBase + path) else { throw HostingError.unsupported("Bad GitHub URL: \(path)") }
        return url
    }

    /// The account itself, then its organizations.
    func owners() async throws -> [RemoteRepositoryOwner] {
        let orgs = try await client.getPages(try url("/user/orgs?per_page=100")).compactMap { $0["login"] as? String }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return [RemoteRepositoryOwner(login: hostingAccount.username, isAccount: true, accountID: account.id)]
            + orgs.map { RemoteRepositoryOwner(login: $0, isAccount: false, accountID: account.id) }
    }

    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        let path = owner.isAccount ? "/user/repos?affiliation=owner&sort=pushed&per_page=100"
            : "/orgs/\(owner.login)/repos?sort=pushed&per_page=100"
        return try await client.getPages(try url(path), maxPages: 20).compactMap { GitHubParser.repository($0, host: hostingAccount.host) }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }
}

// MARK: - GitLab

nonisolated struct GitLabCatalog: RepositoryCatalog {
    let hostingAccount: HostingAccount
    let client: RESTClient
    var account: CatalogAccount {
        CatalogAccount(id: "gitlab:\(hostingAccount.id)", kind: .gitlab, host: hostingAccount.host, title: hostingAccount.title)
    }

    func url(_ path: String) throws -> URL {
        guard let url = URL(string: hostingAccount.apiBase + path) else { throw HostingError.unsupported("Bad GitLab URL: \(path)") }
        return url
    }

    func owners() async throws -> [RemoteRepositoryOwner] {
        let groups = try await client.getPages(try url("/groups?min_access_level=10&per_page=100"))
            .compactMap { group -> RemoteRepositoryOwner? in
                guard let path = group["full_path"] as? String else { return nil }
                return RemoteRepositoryOwner(login: path, isAccount: false, accountID: account.id,
                                             serviceID: (group["id"] as? Int).map(String.init))
            }
            .sorted { $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending }
        return [RemoteRepositoryOwner(login: hostingAccount.username, isAccount: true, accountID: account.id)] + groups
    }

    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        let path = owner.isAccount
            ? "/projects?owned=true&per_page=100&order_by=last_activity_at"
            : "/groups/\(GitLabParser.encoded(owner.login))/projects?include_subgroups=true&per_page=100&order_by=last_activity_at"
        return try await client.getPages(try url(path)).compactMap(CatalogParser.gitlabProject)
    }
}

// MARK: - Bitbucket

nonisolated struct BitbucketCatalog: RepositoryCatalog {
    let hostingAccount: HostingAccount
    let client: RESTClient
    var account: CatalogAccount {
        CatalogAccount(id: "bitbucket:\(hostingAccount.id)", kind: .bitbucket, host: "bitbucket.org", title: hostingAccount.title)
    }

    func owners() async throws -> [RemoteRepositoryOwner] {
        guard let url = URL(string: "\(BitbucketPullRequestHost.api)/user/permissions/workspaces?pagelen=100") else { return [] }
        let values = HostingJSON.object(try await client.get(url))?["values"] as? [HostingJSON.Object] ?? []
        return values.compactMap { $0["workspace"] as? HostingJSON.Object }.compactMap { workspace in
            guard let slug = workspace["slug"] as? String else { return nil }
            return RemoteRepositoryOwner(login: slug, isAccount: slug.caseInsensitiveCompare(hostingAccount.username) == .orderedSame,
                                         accountID: account.id, displayName: workspace["name"] as? String)
        }
        .sorted { ($0.isAccount ? 0 : 1, $0.title.lowercased()) < ($1.isAccount ? 0 : 1, $1.title.lowercased()) }
    }

    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        guard let url = URL(string: "\(BitbucketPullRequestHost.api)/repositories/\(owner.login)?pagelen=100&sort=-updated_on") else { return [] }
        let values = HostingJSON.object(try await client.get(url))?["values"] as? [HostingJSON.Object] ?? []
        return values.compactMap(CatalogParser.bitbucketRepository)
    }
}

// MARK: - Azure DevOps

nonisolated struct AzureDevOpsCatalog: RepositoryCatalog {
    let hostingAccount: HostingAccount
    let client: RESTClient
    private var organization: String { hostingAccount.organization ?? "" }
    var account: CatalogAccount {
        CatalogAccount(id: "azure:\(hostingAccount.id)", kind: .azureDevOps, host: "dev.azure.com/\(organization)", title: hostingAccount.title)
    }

    func owners() async throws -> [RemoteRepositoryOwner] {
        guard let url = URL(string: "https://dev.azure.com/\(organization)/_apis/projects?$top=500&api-version=7.1") else { return [] }
        let values = HostingJSON.object(try await client.get(url))?["value"] as? [HostingJSON.Object] ?? []
        return values.compactMap { project -> RemoteRepositoryOwner? in
            guard let name = project["name"] as? String else { return nil }
            return RemoteRepositoryOwner(login: name, isAccount: false, accountID: account.id, serviceID: project["id"] as? String)
        }
        .sorted { $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending }
    }

    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        let project = owner.login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner.login
        guard let url = URL(string: "https://dev.azure.com/\(organization)/\(project)/_apis/git/repositories?api-version=7.1") else { return [] }
        let values = HostingJSON.object(try await client.get(url))?["value"] as? [HostingJSON.Object] ?? []
        return values.compactMap { CatalogParser.azureRepository($0, organization: organization) }
    }
}

// MARK: - Parsing

nonisolated enum CatalogParser {

    static func gitlabProject(_ raw: HostingJSON.Object) -> RemoteRepository? {
        guard let fullPath = raw["path_with_namespace"] as? String, let web = raw["web_url"] as? String else { return nil }
        let namespace = raw["namespace"] as? HostingJSON.Object
        return RemoteRepository(
            nameWithOwner: fullPath, name: raw["path"] as? String ?? raw["name"] as? String ?? fullPath,
            owner: namespace?["full_path"] as? String ?? "", description: (raw["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            isPrivate: raw["visibility"] as? String != "public", isFork: raw["forked_from_project"] != nil,
            isArchived: raw["archived"] as? Bool ?? false, updatedAt: (raw["last_activity_at"] as? String).flatMap(GitDate.parse),
            webURL: web, sshURL: raw["ssh_url_to_repo"] as? String ?? "", defaultBranch: raw["default_branch"] as? String,
            language: nil, service: .gitlab, cloneURL: raw["http_url_to_repo"] as? String
        )
    }

    static func bitbucketRepository(_ raw: HostingJSON.Object) -> RemoteRepository? {
        guard let fullName = raw["full_name"] as? String else { return nil }
        let links = raw["links"] as? HostingJSON.Object
        let clones = links?["clone"] as? [HostingJSON.Object] ?? []
        func clone(_ name: String) -> String? { clones.first { $0["name"] as? String == name }?["href"] as? String }
        let owner = fullName.split(separator: "/").first.map(String.init) ?? ""
        return RemoteRepository(
            nameWithOwner: fullName, name: raw["slug"] as? String ?? raw["name"] as? String ?? fullName, owner: owner,
            description: (raw["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            isPrivate: raw["is_private"] as? Bool ?? true, isFork: raw["parent"] != nil, isArchived: false,
            updatedAt: (raw["updated_on"] as? String).flatMap(GitDate.parse),
            webURL: (links?["html"] as? HostingJSON.Object)?["href"] as? String ?? "https://bitbucket.org/\(fullName)",
            sshURL: clone("ssh") ?? "git@bitbucket.org:\(fullName).git",
            defaultBranch: (raw["mainbranch"] as? HostingJSON.Object)?["name"] as? String,
            language: (raw["language"] as? String).flatMap { $0.isEmpty ? nil : $0 }, service: .bitbucket,
            // Bitbucket's HTTPS clone URL carries the username, which git then asks a password for.
            cloneURL: clone("https").map(Self.withoutUser)
        )
    }

    static func azureRepository(_ raw: HostingJSON.Object, organization: String) -> RemoteRepository? {
        guard let name = raw["name"] as? String else { return nil }
        let project = raw["project"] as? HostingJSON.Object
        let projectName = project?["name"] as? String ?? ""
        let web = raw["webUrl"] as? String ?? ""
        return RemoteRepository(
            nameWithOwner: "\(organization)/\(projectName)/\(name)", name: name, owner: projectName,
            description: nil, isPrivate: project?["visibility"] as? String != "public", isFork: raw["isFork"] as? Bool ?? false,
            isArchived: raw["isDisabled"] as? Bool ?? false,
            updatedAt: (project?["lastUpdateTime"] as? String).flatMap(GitDate.parse),
            webURL: web, sshURL: raw["sshUrl"] as? String ?? "",
            defaultBranch: (raw["defaultBranch"] as? String)?.withoutHeadsPrefix, language: nil, service: .azureDevOps,
            cloneURL: (raw["remoteUrl"] as? String).map(Self.withoutUser)
        )
    }

    /// `https://user@host/path` → `https://host/path`.
    static func withoutUser(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        components.user = nil
        components.password = nil
        return components.string ?? url
    }
}
