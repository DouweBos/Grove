// Dialogs/Forms/GitBranchForms.swift
// GroveUIKit
//
// Creating, renaming, deleting, tracking, merging and rebasing branches.

#if os(macOS)
import Foundation
import GroveKit

public struct GitCreateBranchForm: GitDialogForm, Equatable {
    public var name = ""
    public var start: String
    public var checkout = true
    /// The new branch pushes to and pulls from `start`.
    public var track = false
    public var pin = false
    /// Recorded so pulls can offer it; empty means none.
    public var parent: String

    public init(start: String, localBranches: [String]) {
        self.start = start
        parent = localBranches.contains(start) ? start : ""
    }

    public var isValid: Bool { RefName.isValid(name.trimmed) && !start.isEmpty }

    public var commands: [GitCommand] {
        guard isValid else { return [] }
        return [.createBranch(name: name.trimmed, from: start, checkout: checkout, track: track,
                              parent: parent.isEmpty ? nil : parent)]
    }

    public func submit(in context: GitDialogContext, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(in: context)
        try await perform(commands, in: context, progress: progress)
        if pin { await context.pinBranch?(name.trimmed) }
        // A checkout isn't undone by deleting the branch, so only a plain one is recorded.
        if !checkout {
            context.undo?.record(GitUndoManager.createBranchAction(branchName: name.trimmed, repository: context.repository,
                                                                   commands: context.commands))
        }
    }
}

public struct GitRenameBranchForm: GitDialogForm, Equatable {
    /// Nil renames the checked-out branch.
    public let original: String?
    public var name: String

    public init(branch: String?, current: String?) {
        original = branch
        name = branch ?? current ?? ""
    }

    public var isValid: Bool { RefName.isValid(name.trimmed) && name.trimmed != original }

    public var commands: [GitCommand] {
        guard isValid else { return [] }
        guard let original else { return [.renameCurrentBranch(to: name.trimmed)] }
        return [.renameBranch(from: original, to: name.trimmed)]
    }
}

public struct GitDeleteBranchForm: GitDialogForm, Equatable {
    public let branch: BranchInfo
    public var force = false
    /// Also deletes its upstream on the remote.
    public var deleteRemote = false
    /// Removes the worktree that has it checked out first.
    public var removeWorktree = false
    public var discardWorktreeChanges = false

    public init(branch: BranchInfo) {
        self.branch = branch
    }

    /// "origin" and "feature/x" from an upstream like "origin/feature/x".
    public var upstream: (remote: String, name: String)? {
        guard let upstream = branch.upstreamShortName, let slash = upstream.firstIndex(of: "/") else { return nil }
        return (String(upstream[..<slash]), String(upstream[upstream.index(after: slash)...]))
    }

    public var commands: [GitCommand] {
        var result: [GitCommand] = [.deleteBranch(name: branch.name, force: force)]
        if deleteRemote, let upstream { result.append(.deleteRemoteBranch(name: upstream.name, remote: upstream.remote)) }
        return result
    }

    public func submit(in context: GitDialogContext, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(in: context)
        if removeWorktree, let worktrees = context.worktrees, let worktree = worktrees.checkingOut(branch) {
            try await worktrees.remove(worktree, discardWorktreeChanges, branch, force)
        } else {
            try await context.commands.perform(.deleteBranch(name: branch.name, force: force))
            context.undo?.record(GitUndoManager.deleteBranchAction(branchName: branch.name, sha: branch.targetSHA,
                                                                   repository: context.repository, commands: context.commands))
        }
        try await perform(Array(commands.dropFirst()), in: context, progress: progress)
    }
}

public struct GitTrackForm: GitDialogForm, Equatable {
    public let branch: BranchInfo
    /// `remote/branch`.
    public var upstream: String

    /// The current upstream, else a same-named remote branch (on `origin` first), else `remote/branch` on the first remote.
    public init(branch: BranchInfo, remoteBranches: [String], remotes: [RemoteInfo]) {
        self.branch = branch
        let namesakes = remoteBranches.filter { $0.hasSuffix("/\(branch.name)") }
        upstream = branch.upstreamShortName ?? namesakes.first { $0.hasPrefix("origin/") } ?? namesakes.first
            ?? "\(remotes.first?.name ?? "origin")/\(branch.name)"
    }

    public var commands: [GitCommand] {
        let name = upstream.trimmed
        guard !name.isEmpty, name != branch.upstreamShortName else { return [] }
        return [.setUpstream(branch: branch.name, upstream: name)]
    }
}

public struct GitMergeForm: GitDialogForm, Equatable {
    public var branch: String
    /// Lands the branch's changes staged, as one commit to make.
    public var squash = false

    public init(candidates: [String]) {
        branch = candidates.first ?? ""
    }

    public var commands: [GitCommand] { branch.isEmpty ? [] : [.merge(branch, squash: squash)] }
}

public struct GitRebaseForm: GitDialogForm, Equatable {
    public var onto: String
    /// Stashes uncommitted changes first and restores them afterwards.
    public var autoStash = false

    public init(candidates: [String]) {
        onto = candidates.first ?? ""
    }

    public var commands: [GitCommand] { commands(stashed: false) }

    public func commands(stashed: Bool) -> [GitCommand] {
        guard !onto.isEmpty else { return [] }
        return stashed ? [.stash(message: Self.stashMessage, includeUntracked: true, keepIndex: false, paths: nil),
                          .rebase(onto: onto), .applyStash(index: 0, drop: true)] : [.rebase(onto: onto)]
    }

    public func submit(in context: GitDialogContext, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(in: context)
        let stashed = autoStash ? try await stashIfDirty(context, message: Self.stashMessage) : false
        try await perform(Array(commands(stashed: stashed).dropFirst(stashed ? 1 : 0)), in: context, progress: progress)
    }

    static let stashMessage = "Auto-stash before rebase"
}
#endif
