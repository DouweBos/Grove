// Commands/GitCommandPerforming.swift
// GroveKit

import Foundation

/// Runs a repository's mutations. The default runs git; an app can wrap its host's commands instead.
public protocol GitCommandPerforming {
    var features: GitFeatures { get }
    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws
}

extension GitCommandPerforming {
    public func perform(_ command: GitCommand) async throws {
        try await perform(command, progress: nil)
    }

    /// Throws for a command this repository doesn't support, so no caller can slip one through.
    public func requireSupport(for command: GitCommand) throws {
        guard let missing = GitFeature.allCases.first(where: {
            command.requiredFeatures.contains($0) && !features.contains($0)
        }) else { return }
        throw GitFeatureError(feature: missing, reason: features.unavailableReason(missing) ?? "")
    }
}

public nonisolated struct GitFeatureError: LocalizedError, Equatable {
    public let feature: GitFeature
    public let reason: String

    public var errorDescription: String? { reason }
}

/// Runs each command on the repository.
public struct RepositoryCommands: GitCommandPerforming {
    public let features: GitFeatures
    private let repository: any GitRepositoryProtocol

    public init(repository: any GitRepositoryProtocol, features: GitFeatures = .all) {
        self.repository = repository
        self.features = features
    }

    public func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(for: command)
        switch command {
        case .fetch(let remote):
            try await repository.fetch(remote: remote, progress: progress)
        case .pull(let remote, let branch, let strategy, let options):
            try await repository.pull(remote: remote, branch: branch, strategy: strategy, options: options, progress: progress)
        case .push(let remote, let branch, let lease, let setUpstream, let options):
            try await repository.push(remote: remote, branch: branch, forceWithLease: lease, setUpstream: setUpstream,
                                      options: options, progress: progress)
        case .createBranch(let name, let start, let checkout, let track, let parent):
            _ = try await repository.createBranch(name: name, from: start, checkout: checkout, track: track, parent: parent)
        case .renameBranch(let old, let new):
            try await repository.renameBranch(oldName: old, newName: new)
        case .deleteBranch(let name, let force):
            try await repository.deleteBranch(name: name, force: force)
        case .deleteRemoteBranch(let name, let remote):
            try await repository.deleteRemoteBranch(name: name, remote: remote)
        case .setUpstream(let branch, let upstream):
            try await repository.setUpstream(of: branch, to: upstream)
        case .checkout(let name):
            try await repository.checkout(branch: name)
        case .merge(let branch, let squash):
            try await repository.merge(branch: branch, squash: squash)
        case .rebase(let branch):
            try await repository.rebase(onto: branch)
        case .createTag(let name, let sha, let message, let sign):
            _ = try await repository.createTag(name: name, at: sha, message: message, sign: sign)
        case .deleteTag(let name):
            try await repository.deleteTag(name: name)
        case .pushTag(let name, let remote):
            try await repository.pushTag(name: name, remote: remote)
        case .pushAllTags(let remote):
            try await repository.pushAllTags(remote: remote)
        case .addRemote(let name, let url):
            try await repository.addRemote(name: name, url: url)
        case .removeRemote(let name):
            try await repository.removeRemote(name: name)
        case .setRemoteURL(let url, let remote):
            try await repository.setRemoteURL(url, forRemote: remote)
        case .renameRemote(let old, let new):
            try await repository.renameRemote(from: old, to: new)
        case .pruneRemote(let name):
            try await repository.pruneRemote(name: name)
        case .stash(let message, let untracked, let keepIndex, let paths):
            try await repository.stashCreate(message: message, includeUntracked: untracked, keepIndex: keepIndex, paths: paths)
        case .branchFromStash(let index, let name):
            try await repository.stashBranch(index: index, name: name)
        case .applyStash(let index, let drop):
            try await repository.stashApply(index: index, drop: drop)
        case .dropStash(let index):
            try await repository.stashDrop(index: index)
        case .snapshot(let message, let untracked):
            _ = try await repository.saveSnapshot(message: message, includeUntracked: untracked)
        }
    }
}
