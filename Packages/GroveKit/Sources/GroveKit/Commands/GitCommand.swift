// Commands/GitCommand.swift
// GroveKit
//
// The mutations an app may want to run its own way, e.g. through a host that holds locks and rules.

import Foundation

public nonisolated enum GitCommand: Sendable, Equatable {
    case fetch(remote: String?)
    case pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions)
    case push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions)
    case createBranch(name: String, from: String?, checkout: Bool, track: Bool, parent: String?)
    case renameBranch(from: String, to: String)
    case deleteBranch(name: String, force: Bool)
    case deleteRemoteBranch(name: String, remote: String)
    case setUpstream(branch: String, upstream: String?)
    case checkout(String)
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

    /// Everything the command needs; all of it has to be supported.
    public var requiredFeatures: Set<GitFeature> {
        switch self {
        // A stash's branch is the host's to allow in a worktree too, so it needs no feature.
        case .fetch, .stash, .branchFromStash, .applyStash, .dropStash, .snapshot: []
        case .pull(_, _, _, let options): options.skipHooks ? [.skipHooks] : []
        case .push(_, _, _, _, let options):
            Set([.push] + (options.skipHooks ? [.skipHooks] : []))
        case .createBranch(_, _, let checkout, _, _): checkout ? [.createBranch, .checkout] : [.createBranch]
        case .renameBranch, .deleteBranch, .setUpstream: [.editBranches]
        case .deleteRemoteBranch: [.editBranches, .push]
        case .checkout: [.checkout]
        case .merge: [.merge]
        case .rebase: [.rebase]
        case .createTag, .deleteTag: [.tag]
        case .pushTag, .pushAllTags: [.tag, .push]
        case .addRemote, .removeRemote, .setRemoteURL, .renameRemote, .pruneRemote: [.remotes]
        }
    }
}
