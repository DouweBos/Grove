// ViewModels/RefActionsViewModel.swift
// GroveKit
//
// Branch and tag actions a refs list offers: checkout, rename, delete, merge, rebase.
// Remotes, submodules and worktrees are in RefActionsViewModel+Remotes.swift.

import Foundation
import Observation

/// Git actions on the refs of one repository, for a sidebar or refs list. The app shows `errorMessage` and `activity`.
@MainActor
@Observable
public final class RefActionsViewModel {

    public let repository: any GitRepositoryProtocol
    /// Shared with the app's other views; read for the current branch and worktrees.
    public let refs: RepositoryRefs

    /// Refreshes every view after a mutation; without it only `refs` re-reads.
    @ObservationIgnored public var onRepositoryChanged: (() async -> Void)?
    /// Reports each action this view model runs, e.g. to the app's telemetry.
    @ObservationIgnored public var onAction: GroveKitActionHandler?
    @ObservationIgnored public var undoManager: GitUndoManager?
    /// A removed worktree's path, then the main worktree's, so views showing it can move.
    @ObservationIgnored public var onWorktreeRemoved: ((String, String?) -> Void)?

    /// The last failed action.
    public private(set) var errorMessage: String?
    /// A running action, e.g. "Cloning vendor/icons…".
    public private(set) var activity: String?

    public init(repository: any GitRepositoryProtocol, refs: RepositoryRefs) {
        self.repository = repository
        self.refs = refs
    }

    public func dismissError() { errorMessage = nil }

    /// Call after anything that changed refs or the working tree.
    public func didChangeRepository() async {
        if let onRepositoryChanged { await onRepositoryChanged() } else { await refs.refresh() }
    }

    /// Runs a git mutation with `title` showing, then refreshes every view whether or not it failed.
    public func perform(_ action: GroveKitAction, _ title: String, _ work: () async throws -> Void) async {
        activity = title
        defer { activity = nil }
        do {
            try await work()
            onAction?(action, true)
        } catch {
            errorMessage = error.localizedDescription
            onAction?(action, false)
        }
        await didChangeRepository()
    }

    /// Runs `work`, refreshing every view when it succeeds and keeping its failure in `errorMessage`.
    func run(_ action: GroveKitAction, _ work: () async throws -> Void) async {
        do {
            try await work()
            onAction?(action, true)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
            onAction?(action, false)
        }
    }

    /// Like `run`, for actions that throw to a dialog instead of setting `errorMessage`.
    func reporting<T>(_ action: GroveKitAction, _ work: () async throws -> T) async throws -> T {
        do {
            let result = try await work()
            onAction?(action, true)
            return result
        } catch {
            onAction?(action, false)
            throw error
        }
    }

    // MARK: - Branches

    private var headName: String? { refs.localBranches.first(where: \.isHEAD)?.name }

    public func checkout(branch: BranchInfo) async {
        await checkout(named: branch.name)
    }

    /// Checks out a remote branch as a local tracking branch (git's DWIM), or the existing local branch of the same name.
    public func checkout(remoteBranch branch: BranchInfo) async {
        await checkout(named: Self.shortName(of: branch))
    }

    private func checkout(named name: String) async {
        let previous = headName
        do {
            try await repository.checkout(branch: name)
            onAction?(.checkout, true)
        } catch {
            errorMessage = error.localizedDescription
            onAction?(.checkout, false)
            return
        }
        // Detached HEAD has no branch to return to, so it isn't recorded.
        if let previous, previous != name {
            undoManager?.record(GitUndoManager.checkoutAction(targetBranch: name, previousBranch: previous,
                                                              repository: repository))
        }
        await didChangeRepository()
    }

    /// Throws so a rename dialog can show the failure and stay open.
    public func renameBranch(_ branch: BranchInfo, to newName: String) async throws {
        try await reporting(.branchRename) { try await repository.renameBranch(oldName: branch.name, newName: newName) }
        await didChangeRepository()
    }

    public func deleteBranch(_ branch: BranchInfo, force: Bool = false) async {
        do {
            try await repository.deleteBranch(name: branch.name, force: force)
            onAction?(.branchDelete, true)
        } catch {
            errorMessage = error.localizedDescription
            onAction?(.branchDelete, false)
            return
        }
        recordBranchDeletion(branch)
        await didChangeRepository()
    }

    /// For a dialog that deletes the branch itself, so the deletion can still be undone.
    public func recordBranchDeletion(_ branch: BranchInfo) {
        undoManager?.record(GitUndoManager.deleteBranchAction(branchName: branch.name, sha: branch.targetSHA,
                                                              repository: repository))
    }

    /// Merges `branch` into HEAD.
    public func merge(branch: BranchInfo) async {
        await run(.merge) { try await repository.merge(branch: branch.name) }
    }

    /// Rebases HEAD onto `branch`.
    public func rebase(onto branch: BranchInfo) async {
        await run(.rebase) { try await repository.rebase(onto: branch.name) }
    }

    public func cherryPick(sha: String) async {
        await run(.cherryPick) { try await repository.cherryPick(commit: sha) }
    }

    /// Applies the stash at `index`, keeping it in the list.
    public func stashApply(index: Int) async {
        await run(.stashApply) { try await repository.stashApply(index: index, drop: false) }
    }

    public func deleteTag(_ tag: TagInfo) async {
        await run(.tagDelete) { try await repository.deleteTag(name: tag.name) }
    }

    /// Deletes a remote-tracking branch's branch on its remote.
    public func deleteRemoteBranch(_ branch: BranchInfo) async {
        guard let remote = branch.remoteName else { return }
        await run(.branchDelete) { try await repository.deleteRemoteBranch(name: Self.shortName(of: branch), remote: remote) }
    }

    /// Remote branch name without its "remote/" prefix.
    public nonisolated static func shortName(of branch: BranchInfo) -> String {
        if let remote = branch.remoteName, branch.name.hasPrefix(remote + "/") {
            return String(branch.name.dropFirst(remote.count + 1))
        }
        return branch.name
    }
}
