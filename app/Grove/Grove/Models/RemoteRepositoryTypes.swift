// Models/RemoteRepositoryTypes.swift
// Grove
//
// Repositories on the hosting accounts, for the cloud browser.

import Foundation

nonisolated struct RemoteRepositoryOwner: Identifiable, Hashable, Sendable {
    var id: String { "\(accountID)/\(login)" }
    let login: String
    /// The signed-in account itself rather than an organization it belongs to.
    let isAccount: Bool
    /// The `CatalogAccount` the owner was listed under.
    var accountID = ""
    /// Shown instead of `login` where the service has a friendlier name (Bitbucket workspaces, Azure projects).
    var displayName: String?
    /// The service's own id, where creating a repository needs it (GitLab group, Azure DevOps project).
    var serviceID: String?

    var title: String { displayName ?? login }
}

/// What "New Remote Repository" asks a service to create.
nonisolated struct NewRemoteRepository: Equatable, Sendable {
    var owner: RemoteRepositoryOwner
    var name: String
    var description = ""
    var isPrivate = true

    /// Bitbucket and GitLab address repositories by a slug: lowercase, dashes for spaces.
    var slug: String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

nonisolated struct RemoteRepository: Identifiable, Hashable, Sendable {
    var id: String { "\(service.rawValue):\(nameWithOwner)" }
    let nameWithOwner: String
    let name: String
    let owner: String
    let description: String?
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let updatedAt: Date?
    let webURL: String
    let sshURL: String
    let defaultBranch: String?
    let language: String?
    var service: HostingServiceKind = .github
    /// Set where the HTTPS clone URL isn't the web URL plus `.git` (Azure DevOps, Bitbucket).
    var cloneURL: String?

    var httpsCloneURL: String { cloneURL ?? (webURL.hasSuffix(".git") ? webURL : webURL + ".git") }

    /// HTTPS like Tower: Grove answers its prompts with the account token, so it works without an SSH key.
    var defaultCloneURL: String { httpsCloneURL }

    /// "github.com/owner/name", lowercased, for matching local clones by any of their remote URLs.
    var matchKey: String? { RemoteURLKey.make(webURL) }
}

nonisolated enum RemoteURLKey {
    /// Normalizes `git@host:owner/name.git`, `ssh://git@host/owner/name` and `https://user@host/owner/name.git`
    /// to `host/owner/name` so a local remote can be matched to a hosted repository.
    static func make(_ url: String) -> String? {
        var rest = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Local remotes (paths, file URLs) can't match a hosted repository.
        guard !rest.hasPrefix("/"), !rest.hasPrefix("file:"), !rest.hasPrefix("."), !rest.hasPrefix("~") else { return nil }
        for scheme in ["https://", "http://", "ssh://", "git://"] where rest.hasPrefix(scheme) {
            rest = String(rest.dropFirst(scheme.count))
        }
        if let at = rest.firstIndex(of: "@"), rest[..<at].firstIndex(of: "/") == nil {
            rest = String(rest[rest.index(after: at)...])
        }
        if let colon = rest.firstIndex(of: ":"), rest[..<colon].firstIndex(of: "/") == nil {
            // scp-style `host:owner/name`, or `host:port/owner/name`.
            let after = rest[rest.index(after: colon)...]
            let pathStart = after.first?.isNumber == true ? after.drop(while: { $0.isNumber }).dropFirst() : after
            rest = String(rest[..<colon]) + "/" + pathStart
        }
        if rest.hasSuffix(".git") { rest = String(rest.dropLast(4)) }
        while rest.hasSuffix("/") { rest = String(rest.dropLast()) }
        let parts = rest.split(separator: "/")
        return parts.count >= 3 ? parts.joined(separator: "/") : nil
    }
}
