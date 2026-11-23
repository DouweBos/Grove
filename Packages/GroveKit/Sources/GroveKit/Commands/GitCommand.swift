// Commands/GitCommand.swift
// GroveKit
//
// The mutations an app may want to run its own way, e.g. through a host that holds locks and rules.

import Foundation

public nonisolated enum GitCommand: Sendable, Equatable {
    /// A nil remote fetches every remote.
    case fetch(remote: String?)
    case pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions)
    case push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions)
    /// Pushes a local branch other than HEAD's, as `as` on the remote.
    case pushBranch(String, remote: String, as: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions)
    /// Fetches, integrates the upstream and pushes; a branch without one starts tracking `remote`.
    case sync(remote: String?, strategy: PullStrategy)
    case createBranch(name: String, from: String?, checkout: Bool, track: Bool, parent: String?)
    case renameBranch(from: String, to: String)
    /// The checked-out branch; a host may allow it where other branch edits aren't, e.g. on a session's own branch.
    case renameCurrentBranch(to: String)
    case deleteBranch(name: String, force: Bool)
    case deleteRemoteBranch(name: String, remote: String)
    case setUpstream(branch: String, upstream: String?)
    case checkout(String)
    /// Checks out with the uncommitted changes stashed first and restored after.
    case stashAndCheckout(String)
    /// Checks out after throwing away unstaged changes to tracked files.
    case discardAndCheckout(String)
    case merge(String, squash: Bool)
    case rebase(onto: String)
    case createTag(name: String, at: String?, message: String?, sign: Bool)
    case deleteTag(String)
    case pushTag(String, remote: String?)
    case pushAllTags(remote: String?)
    case addRemote(name: String, url: String)
    case removeRemote(String)
    case setRemoteURL(String, remote: String)
    case renameRemote(from: String, to: String)
    case pruneRemote(String)
    case stash(message: String?, includeUntracked: Bool, keepIndex: Bool, paths: [String]?)
    case branchFromStash(index: Int, name: String)
    case applyStash(index: Int, drop: Bool)
    case dropStash(index: Int)
    case snapshot(message: String, includeUntracked: Bool)
    /// Writes an edited merge result over a conflicted file and marks it resolved.
    case saveConflictResolution(path: String, contents: String)
    case cherryPick(String)
    case revert(String)
    /// Moves HEAD's branch to a commit.
    case reset(to: String, mode: ResetMode)
    case reword(String, message: String)
    /// Folds commits, oldest first, into one.
    case squash([String], message: String)
    case drop(String)
    /// `steps` oldest first.
    case rebaseInteractive(onto: String, steps: [RebaseStep])

    /// Everything the command needs; all of it has to be supported.
    public var requiredFeatures: Set<GitFeature> {
        switch self {
        // A stash's branch is the host's to allow in a worktree too, so it needs no feature.
        case .fetch, .stash, .branchFromStash, .applyStash, .dropStash, .snapshot, .renameCurrentBranch,
             .saveConflictResolution: []
        // History rewrites only touch the checked-out branch, which every repository may change.
        case .cherryPick, .revert, .reset, .reword, .squash, .drop, .rebaseInteractive: []
        case .pull(_, _, _, let options): Self.features(of: options)
        case .push(_, _, _, _, let options), .pushBranch(_, _, _, _, _, let options):
            Self.features(of: options).union([.push])
        case .sync: [.push]
        case .createBranch(_, _, let checkout, _, _): checkout ? [.createBranch, .checkout] : [.createBranch]
        case .renameBranch, .deleteBranch, .setUpstream: [.editBranches]
        case .deleteRemoteBranch: [.editBranches, .push]
        case .checkout, .stashAndCheckout, .discardAndCheckout: [.checkout]
        case .merge: [.merge]
        case .rebase: [.rebase]
        case .createTag, .deleteTag: [.tag]
        case .pushTag, .pushAllTags: [.tag, .push]
        case .addRemote, .removeRemote, .setRemoteURL, .renameRemote, .pruneRemote: [.remotes]
        }
    }

    private static func features(of options: PullOptions) -> Set<GitFeature> {
        Set((options.skipHooks ? [GitFeature.skipHooks] : []) + (options.verifySignatures ? [.verifySignatures] : []))
    }

    private static func features(of options: PushOptions) -> Set<GitFeature> {
        Set((options.skipHooks ? [GitFeature.skipHooks] : []) + (options.recurseSubmodules != nil ? [.recurseSubmodules] : []))
    }
}
