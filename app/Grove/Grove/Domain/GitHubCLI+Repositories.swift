// Domain/GitHubCLI+Repositories.swift
// Grove

import Foundation

extension GitHubCLI {

    /// The signed-in account, then the organizations it belongs to.
    nonisolated static func repositoryOwners() async throws -> [RemoteRepositoryOwner] {
        let login = try await run(["api", "user", "--jq", ".login"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let orgs = try await run(["api", "user/orgs", "--paginate", "--jq", ".[].login"])
            .split(whereSeparator: \.isNewline).map(String.init)
        return [RemoteRepositoryOwner(login: login, isAccount: true)]
            + orgs.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { RemoteRepositoryOwner(login: $0, isAccount: false) }
    }

    nonisolated static func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        var arguments = ["repo", "list"]
        // Without an owner `gh` lists the signed-in account's own repositories.
        if !owner.isAccount { arguments.append(owner.login) }
        arguments += ["--limit", "2000", "--json", RemoteRepositoryParser.fields]
        return try RemoteRepositoryParser.parse(Data(try await run(arguments).utf8))
    }
}

nonisolated enum RemoteRepositoryParser {
    static let fields = "name,nameWithOwner,owner,description,isPrivate,isFork,isArchived,updatedAt,url,sshUrl,defaultBranchRef,primaryLanguage"

    private struct Row: Decodable {
        struct Login: Decodable { let login: String }
        struct Named: Decodable { let name: String }
        let name: String
        let nameWithOwner: String
        let owner: Login
        let description: String?
        let isPrivate: Bool
        let isFork: Bool
        let isArchived: Bool
        let updatedAt: String?
        let url: String
        let sshUrl: String
        let defaultBranchRef: Named?
        let primaryLanguage: Named?
    }

    /// Parses `gh repo list --json <fields>`, most recently updated first.
    static func parse(_ data: Data) throws -> [RemoteRepository] {
        try JSONDecoder().decode([Row].self, from: data).map { row in
            RemoteRepository(
                nameWithOwner: row.nameWithOwner, name: row.name, owner: row.owner.login,
                description: row.description.flatMap { $0.isEmpty ? nil : $0 },
                isPrivate: row.isPrivate, isFork: row.isFork, isArchived: row.isArchived,
                updatedAt: row.updatedAt.flatMap(GitDate.parse),
                webURL: row.url, sshURL: row.sshUrl,
                defaultBranch: row.defaultBranchRef?.name, language: row.primaryLanguage?.name
            )
        }
        .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }
}
