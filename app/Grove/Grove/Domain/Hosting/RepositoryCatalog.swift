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
}

@MainActor
enum RepositoryCatalogs {

    /// Every account Grove can list repositories for: gh and glab sign-ins, then the stored REST accounts.
    static func all(accounts: HostingAccountStore? = nil, http: any HTTPClient = URLSessionHTTPClient()) async -> [any RepositoryCatalog] {
        var catalogs: [any RepositoryCatalog] = []
        if GitHubCLI.isInstalled, let signedIn = try? await GitHubCLI.authStatus() {
            // gh's repository listing follows its default host; other GitHub hosts are left to their own clients.
            for status in signedIn where status.host == "github.com" {
                catalogs.append(GitHubCatalog(login: status.account ?? ""))
            }
        }
        for status in await GitLabCLI.authStatus() {
            catalogs.append(GitLabCatalog(host: status.host, username: status.account ?? ""))
        }
        let store = accounts ?? .shared
        for account in store.accounts {
            guard let secret = store.secret(for: account) else { continue }
            let client = RESTClient(credentials: RESTCredentials(account: account, secret: secret), http: http)
            switch account.kind {
            case .bitbucket: catalogs.append(BitbucketCatalog(hostingAccount: account, client: client))
            case .azureDevOps: catalogs.append(AzureDevOpsCatalog(hostingAccount: account, client: client))
            case .github, .gitlab: break
            }
        }
        return catalogs
    }
}

// MARK: - GitHub

nonisolated struct GitHubCatalog: RepositoryCatalog {
    let login: String
    var account: CatalogAccount { CatalogAccount(id: "github:github.com:\(login)", kind: .github, host: "github.com", title: login) }

    func owners() async throws -> [RemoteRepositoryOwner] {
        try await GitHubCLI.repositoryOwners().map {
            RemoteRepositoryOwner(login: $0.login, isAccount: $0.isAccount, accountID: account.id)
        }
    }

    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        try await GitHubCLI.repositories(of: owner)
    }
}

// MARK: - GitLab

nonisolated struct GitLabCatalog: RepositoryCatalog {
    let host: String
    let username: String
    var account: CatalogAccount { CatalogAccount(id: "gitlab:\(host):\(username)", kind: .gitlab, host: host, title: username) }

    func owners() async throws -> [RemoteRepositoryOwner] {
        let groups = HostingJSON.objects(try await GitLabCLI.api("groups?min_access_level=10&per_page=100", host: host, paginate: true))
            .compactMap { $0["full_path"] as? String }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return [RemoteRepositoryOwner(login: username, isAccount: true, accountID: account.id)]
            + groups.map { RemoteRepositoryOwner(login: $0, isAccount: false, accountID: account.id) }
    }

    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        let path = owner.isAccount
            ? "projects?owned=true&per_page=100&order_by=last_activity_at"
            : "groups/\(owner.login.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? owner.login)/projects"
                + "?include_subgroups=true&per_page=100&order_by=last_activity_at"
        return HostingJSON.objects(try await GitLabCLI.api(path, host: host, paginate: true)).compactMap(CatalogParser.gitlabProject)
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
        return values.compactMap { $0["name"] as? String }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { RemoteRepositoryOwner(login: $0, isAccount: false, accountID: account.id) }
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
