// Models/RemoteRepositoryTypes.swift
// Grove
//
// Repositories on a hosting account (GitHub via `gh`), for the cloud browser.

import Foundation

nonisolated struct RemoteRepositoryOwner: Identifiable, Hashable, Sendable {
    var id: String { login }
    let login: String
    /// The signed-in account itself rather than an organization it belongs to.
    let isAccount: Bool
}

nonisolated struct RemoteRepository: Identifiable, Hashable, Sendable {
    var id: String { nameWithOwner }
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

    var httpsCloneURL: String { webURL.hasSuffix(".git") ? webURL : webURL + ".git" }

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
