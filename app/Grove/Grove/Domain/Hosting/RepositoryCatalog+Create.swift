// Domain/Hosting/RepositoryCatalog+Create.swift
// Grove
//
// "New Remote Repository" on each service.

import Foundation

extension GitHubCatalog {

    static func createBody(_ request: NewRemoteRepository) -> [String: Any] {
        ["name": request.name, "description": request.description, "private": request.isPrivate]
    }

    /// The account's own repositories go to `/user/repos`, an organization's to `/orgs/{org}/repos`.
    func createRepository(_ request: NewRemoteRepository) async throws -> RemoteRepository {
        let path = request.owner.isAccount ? "/user/repos" : "/orgs/\(request.owner.login)/repos"
        guard let url = URL(string: hostingAccount.apiBase + path) else { throw HostingError.unsupported("Bad owner name.") }
        let data = try await client.send("POST", url, json: Self.createBody(request))
        guard let created = HostingJSON.object(data).flatMap({ GitHubParser.repository($0, host: hostingAccount.host) }) else {
            throw HostingError.unsupported("GitHub didn't return the new repository.")
        }
        return created
    }
}

extension GitLabCatalog {

    /// A group's projects need its namespace id; the account's own go to its personal namespace.
    static func createFields(_ request: NewRemoteRepository) -> [String: String] {
        var fields = ["name": request.name, "path": request.slug, "visibility": request.isPrivate ? "private" : "public"]
        if !request.description.isEmpty { fields["description"] = request.description }
        if !request.owner.isAccount, let id = request.owner.serviceID { fields["namespace_id"] = id }
        return fields
    }

    func createRepository(_ request: NewRemoteRepository) async throws -> RemoteRepository {
        let data = try await client.send("POST", try url("/projects"), json: Self.createFields(request))
        guard let created = HostingJSON.object(data).flatMap(CatalogParser.gitlabProject) else {
            throw HostingError.unsupported("GitLab didn't return the new project.")
        }
        return created
    }
}

extension BitbucketCatalog {

    static func createBody(_ request: NewRemoteRepository) -> [String: Any] {
        ["scm": "git", "name": request.name, "is_private": request.isPrivate, "description": request.description]
    }

    func createRepository(_ request: NewRemoteRepository) async throws -> RemoteRepository {
        guard let url = URL(string: "\(BitbucketPullRequestHost.api)/repositories/\(request.owner.login)/\(request.slug)") else {
            throw HostingError.unsupported("Bad repository name.")
        }
        let data = try await client.send("POST", url, json: Self.createBody(request))
        guard let created = HostingJSON.object(data).flatMap(CatalogParser.bitbucketRepository) else {
            throw HostingError.unsupported("Bitbucket didn't return the new repository.")
        }
        return created
    }
}

extension AzureDevOpsCatalog {

    var supportsVisibilityAndDescription: Bool { false }

    static func createBody(_ request: NewRemoteRepository) -> [String: Any] {
        var body: [String: Any] = ["name": request.name]
        if let project = request.owner.serviceID { body["project"] = ["id": project] }
        return body
    }

    func createRepository(_ request: NewRemoteRepository) async throws -> RemoteRepository {
        let organization = hostingAccount.organization ?? ""
        let project = request.owner.login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.owner.login
        guard let url = URL(string: "https://dev.azure.com/\(organization)/\(project)/_apis/git/repositories?api-version=7.1") else {
            throw HostingError.unsupported("Bad project name.")
        }
        let data = try await client.send("POST", url, json: Self.createBody(request))
        guard let created = HostingJSON.object(data).flatMap({ CatalogParser.azureRepository($0, organization: organization) }) else {
            throw HostingError.unsupported("Azure DevOps didn't return the new repository.")
        }
        return created
    }
}
