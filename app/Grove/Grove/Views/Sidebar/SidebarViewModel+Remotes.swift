// Views/Sidebar/SidebarViewModel+Remotes.swift
// Grove

import Foundation

extension SidebarViewModel {

    /// `origin` for a repository without remotes, otherwise nothing to guess.
    var suggestedRemoteName: String {
        remotes.contains { $0.name == "origin" } ? "" : "origin"
    }

    /// Why `name` can't be added, or nil when it can; git still has the final say on the format.
    func remoteNameProblem(_ name: String) -> String? {
        if name.isEmpty { return "Enter a name." }
        if name.contains(where: \.isWhitespace) { return "Names can\u{2019}t contain spaces." }
        if remotes.contains(where: { $0.name == name }) { return "\u{201C}\(name)\u{201D} already exists." }
        return nil
    }

    /// Throws so the Add Remote sheet can show the failure and stay open; a failed fetch keeps the remote.
    func addRemote(name: String, url: String) async throws {
        try await repository.addRemote(name: name, url: url)
        dismissAddRemote()
        await perform("Fetching \(name)…") { try await repository.fetch(remote: name, progress: nil) }
    }

    func removeRemote(_ remote: RemoteInfo) async {
        await perform("Removing \(remote.name)…") { try await repository.removeRemote(name: remote.name) }
    }
}
