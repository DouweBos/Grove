// Domain/Hosting/RepositoryCatalog+Create.swift
// Grove
//
// "New Remote Repository" on each service.

import Foundation

extension GitHubCatalog {

    /// `gh repo create` creates under the signed-in account unless the name carries an organization.
    static func createArguments(_ request: NewRemoteRepository) -> [String] {
        let name = request.owner.isAccount ? request.name : "\(request.owner.login)/\(request.name)"
        var arguments = ["repo", "create", name, request.isPrivate ? "--private" : "--public"]
        if !request.description.isEmpty { arguments += ["--description", request.description] }
        return arguments
    }

    func createRepository(_ request: NewRemoteRepository) async throws -> RemoteRepository {
        _ = try await GitHubCLI.run(Self.createArguments(request))
        let owner = request.owner.login
        let name = request.name
        return RemoteRepository(
            nameWithOwner: "\(owner)/\(name)", name: name, owner: owner,
            description: request.description.isEmpty ? nil : request.description, isPrivate: request.isPrivate,
            isFork: false, isArchived: false, updatedAt: Date(), webURL: "https://github.com/\(owner)/\(name)",
            sshURL: "git@github.com:\(owner)/\(name).git", defaultBranch: nil, language: nil
        )
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
        let output = try await GitLabCLI.api("projects", host: host, method: "POST", fields: Self.createFields(request))
        guard let created = HostingJSON.objects(output).first.flatMap(CatalogParser.gitlabProject) else {
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
