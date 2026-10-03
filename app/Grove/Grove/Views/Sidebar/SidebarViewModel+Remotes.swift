// Views/Sidebar/SidebarViewModel+Remotes.swift
// Grove

import Foundation
import GroveKit

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
        await perform("Fetching \(name)…") {
            try await repository.fetch(remote: name, progress: nil)
            try await trackMatchingBranches(on: name)
        }
    }

    /// Like a clone: local branches that track nothing start tracking their namesake on the new remote.
    private func trackMatchingBranches(on remote: String) async throws {
        let remoteNames = Set(try await repository.remoteBranches().map(\.name))
        for branch in try await repository.localBranches() where branch.upstream == nil {
            let candidate = "\(remote)/\(branch.name)"
            if remoteNames.contains(candidate) { try await repository.setUpstream(of: branch.name, to: candidate) }
        }
    }

    func removeRemote(_ remote: RemoteInfo) async {
        await perform("Removing \(remote.name)…") { try await repository.removeRemote(name: remote.name) }
    }

    // MARK: - Tracking

    /// Remote branches a local branch can track, e.g. `origin/main`.
    var trackableRemoteBranches: [String] {
        remoteBranches.map(\.name).filter { !$0.hasSuffix("/HEAD") }
    }

    /// The current upstream, else a same-named branch (on `origin` first), else nil.
    func suggestedUpstream(for branch: BranchInfo) -> String? {
        let candidates = trackableRemoteBranches
        if let upstream = branch.upstreamShortName, candidates.contains(upstream) { return upstream }
        let namesakes = candidates.filter { $0.hasSuffix("/\(branch.name)") }
        return namesakes.first { $0.hasPrefix("origin/") } ?? namesakes.first
    }

    /// Throws so the Track sheet can show the failure and stay open.
    func track(_ branch: BranchInfo, remoteBranch: String) async throws {
        try await repository.setUpstream(of: branch.name, to: remoteBranch)
        await didChangeRepository()
    }

    func stopTracking(_ branch: BranchInfo) async {
        await perform("Untracking \(branch.name)…") { try await repository.setUpstream(of: branch.name, to: nil) }
    }
}
