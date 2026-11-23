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

/// A command that ran but had nothing to do, which the person should hear about.
public nonisolated enum GitCommandError: LocalizedError, Equatable {
    case nothingToSnapshot
    case detachedHead

    public var errorDescription: String? {
        switch self {
        case .nothingToSnapshot: "There are no local changes to snapshot."
        case .detachedHead: "No branch is checked out."
        }
    }
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
        case .fetch(let remote?):
            try await repository.fetch(remote: remote, progress: progress)
        case .fetch(nil):
            try await fetchAll(progress: progress)
        case .pull(let remote, let branch, let strategy, let options):
            try await repository.pull(remote: remote, branch: branch, strategy: strategy, options: options, progress: progress)
        case .push(let remote, let branch, let lease, let setUpstream, let options):
            try await repository.push(remote: remote, branch: branch, forceWithLease: lease, setUpstream: setUpstream,
                                      options: options, progress: progress)
        case .pushBranch(let local, let remote, let target, let lease, let setUpstream, let options):
            try await repository.push(branch: local, to: remote, as: target, forceWithLease: lease, setUpstream: setUpstream,
                                      options: options, progress: progress)
        case .sync(let remote, let strategy):
            try await repository.sync(remote: remote, strategy: strategy, progress: progress)
        case .createBranch(let name, let start, let checkout, let track, let parent):
            _ = try await repository.createBranch(name: name, from: start, checkout: checkout, track: track, parent: parent)
        case .renameBranch(let old, let new):
            try await repository.renameBranch(oldName: old, newName: new)
        case .renameCurrentBranch(let new):
            guard let current = repository.currentBranch?.name else { throw GitCommandError.detachedHead }
            try await repository.renameBranch(oldName: current, newName: new)
        case .deleteBranch(let name, let force):
            try await repository.deleteBranch(name: name, force: force)
        case .deleteRemoteBranch(let name, let remote):
            try await repository.deleteRemoteBranch(name: name, remote: remote)
        case .setUpstream(let branch, let upstream):
            try await repository.setUpstream(of: branch, to: upstream)
        case .checkout(let name):
            try await repository.checkout(branch: name)
        case .stashAndCheckout(let name):
            try await stashAndCheckout(name)
        case .discardAndCheckout(let name):
            let tracked = try await repository.status().filter { $0.workdirStatus != .untracked && $0.isChanged }
            try await repository.discardChanges(paths: tracked.map(\.path))
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
            guard try await repository.saveSnapshot(message: message, includeUntracked: untracked) else {
                throw GitCommandError.nothingToSnapshot
            }
        case .saveConflictResolution(let path, let contents):
            try await repository.saveConflictResolution(path: path, contents: contents)
        case .cherryPick(let sha):
            try await repository.cherryPick(commit: sha)
        case .revert(let sha):
            try await repository.revert(commit: sha)
        case .reset(let sha, let mode):
            try await repository.resetToCommit(sha, mode: mode)
        case .reword(let sha, let message):
            try await repository.rewordCommit(sha, newMessage: message)
        case .squash(let shas, let message):
            try await repository.squashCommits(shas, message: message)
        case .drop(let sha):
            try await repository.dropCommit(sha)
        case .rebaseInteractive(let base, let steps):
            try await repository.rebaseInteractive(onto: base, steps: steps)
        }
    }

    /// Every remote in turn, sharing the progress between them.
    private func fetchAll(progress: (@Sendable (Double) -> Void)?) async throws {
        let remotes = try await repository.remotes().map(\.name)
        for (index, remote) in remotes.enumerated() {
            let share = progress.map { report in { @Sendable (value: Double) in report((Double(index) + value) / Double(remotes.count)) } }
            try await repository.fetch(remote: remote, progress: share)
        }
    }

    /// Like the host's: the changes come back after the switch, and stay put when it fails.
    private func stashAndCheckout(_ name: String) async throws {
        let dirty = try await repository.status().contains(where: \.isChanged)
        if dirty { try await repository.stashCreate(message: "Before checking out \(name)", includeUntracked: true, paths: nil) }
        do {
            try await repository.checkout(branch: name)
        } catch {
            if dirty { try? await repository.stashApply(index: 0, drop: true) }
            throw error
        }
        if dirty { try await repository.stashApply(index: 0, drop: true) }
    }
}

extension StatusEntry {
    nonisolated var isChanged: Bool { indexStatus != .unmodified || workdirStatus != .unmodified }
}
