// ViewModels/RefActionsViewModel+Remotes.swift
// GroveKit
//
// Remotes, tracking, submodules and worktrees.

import Foundation

extension RefActionsViewModel {

    // MARK: - Remotes

    /// `origin` for a repository without remotes, otherwise nothing to guess.
    public var suggestedRemoteName: String {
        refs.remotes.contains { $0.name == "origin" } ? "" : "origin"
    }

    /// Why `name` can't be added, or nil when it can; git still has the final say on the format.
    public func remoteNameProblem(_ name: String) -> String? {
        if name.isEmpty { return "Enter a name." }
        if name.contains(where: \.isWhitespace) { return "Names can\u{2019}t contain spaces." }
        if refs.remotes.contains(where: { $0.name == name }) { return "\u{201C}\(name)\u{201D} already exists." }
        return nil
    }

    /// Adds and fetches a remote. Throws when adding fails, for a sheet to show; a failed fetch keeps the remote.
    /// `onAdded` runs before the fetch, e.g. to close that sheet while the fetch shows as `activity`.
    public func addRemote(name: String, url: String, onAdded: () -> Void = {}) async throws {
        try await repository.addRemote(name: name, url: url)
        onAdded()
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

    public func removeRemote(_ remote: RemoteInfo) async {
        await perform("Removing \(remote.name)…") { try await repository.removeRemote(name: remote.name) }
    }

    // MARK: - Tracking

    /// Remote branches a local branch can track, e.g. `origin/main`.
    public var trackableRemoteBranches: [String] {
        refs.remoteBranches.map(\.name).filter { !$0.hasSuffix("/HEAD") }
    }

    /// The current upstream, else a same-named branch (on `origin` first), else nil.
    public func suggestedUpstream(for branch: BranchInfo) -> String? {
        let candidates = trackableRemoteBranches
        if let upstream = branch.upstreamShortName, candidates.contains(upstream) { return upstream }
        let namesakes = candidates.filter { $0.hasSuffix("/\(branch.name)") }
        return namesakes.first { $0.hasPrefix("origin/") } ?? namesakes.first
    }

    /// Throws so a Track sheet can show the failure and stay open.
    public func track(_ branch: BranchInfo, remoteBranch: String) async throws {
        try await repository.setUpstream(of: branch.name, to: remoteBranch)
        await didChangeRepository()
    }

    public func stopTracking(_ branch: BranchInfo) async {
        await perform("Untracking \(branch.name)…") { try await repository.setUpstream(of: branch.name, to: nil) }
    }

    // MARK: - Submodules

    public func initSubmodule(_ submodule: SubmoduleInfo) async {
        await perform("Cloning \(submodule.displayName)…") { try await repository.initSubmodule(path: submodule.path) }
    }

    public func updateSubmodule(_ submodule: SubmoduleInfo, toRemote: Bool) async {
        await perform("Updating \(submodule.displayName)…") {
            try await repository.updateSubmodule(path: submodule.path, toRemote: toRemote)
        }
    }

    public func fetchSubmodule(_ submodule: SubmoduleInfo) async {
        await perform("Fetching \(submodule.displayName)…") { try await repository.fetchSubmodule(path: submodule.path) }
    }

    public func removeSubmodule(_ submodule: SubmoduleInfo) async {
        await perform("Removing \(submodule.displayName)…") { try await repository.removeSubmodule(path: submodule.path) }
    }

    /// Throws so an Add Submodule sheet can show the failure and stay open.
    public func addSubmodule(url: String, path: String, branch: String?) async throws {
        do {
            try await repository.addSubmodule(url: url, path: path, branch: branch)
        } catch {
            await didChangeRepository()
            throw error
        }
        await didChangeRepository()
    }

    /// `icons` for `https://github.com/example/icons.git`.
    public nonisolated static func suggestedSubmodulePath(for url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }

    // MARK: - Worktrees

    /// Whether `worktree` is the one this repository was opened at.
    public func isCurrent(_ worktree: WorktreeInfo) -> Bool {
        WorktreeResolver.isSameFolder(worktree.path, repository.path.path)
    }

    /// Worktrees other than this one; from a linked worktree that includes the main one.
    public var otherWorktrees: [WorktreeInfo] {
        refs.worktrees.filter { !isCurrent($0) }
    }

    /// The other worktree that has `branch` checked out; git won't check it out here too.
    public func worktree(checkingOut branch: BranchInfo) -> WorktreeInfo? {
        otherWorktrees.first { $0.branch == branch.name }
    }

    public var mainWorktreePath: String? { refs.worktrees.first(where: \.isMain)?.path }

    /// The local branch a worktree has checked out, e.g. to offer deleting it with the worktree.
    public func branch(checkedOutIn worktree: WorktreeInfo) -> BranchInfo? {
        guard let name = worktree.branch else { return nil }
        return refs.localBranches.first { $0.name == name }
    }

    /// `git worktree remove`; `force` also discards its uncommitted changes. Throws for a dialog to show.
    public func removeWorktree(_ worktree: WorktreeInfo, force: Bool) async throws {
        try await repository.removeWorktree(path: worktree.path, force: force)
        onWorktreeRemoved?(worktree.path, mainWorktreePath)
    }

    /// Removes `worktree`, then deletes `branch` if given; git won't delete a branch a worktree has checked out.
    /// A retry after the branch failed skips the worktree, which is already gone.
    public func removeWorktree(_ worktree: WorktreeInfo, force: Bool,
                               deleting branch: BranchInfo?, forceBranch: Bool) async throws {
        if refs.worktrees.contains(where: { $0.path == worktree.path }) {
            try await removeWorktree(worktree, force: force)
        }
        guard let branch else { return }
        try await repository.deleteBranch(name: branch.name, force: forceBranch)
        recordBranchDeletion(branch)
    }

    public func pruneWorktrees() async {
        await run { try await repository.pruneWorktrees() }
    }
}
