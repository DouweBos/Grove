// Engine/GitRepository+BranchSync.swift
// GroveKit
//
// Moving branches that aren't checked out: fast-forwarding one from a remote branch, and pushing one to a remote.

import Foundation
import os

extension GitRepository {

    /// Fetches `remoteBranch` from `remote` straight into local `branch`; git refuses unless it's a fast-forward.
    public func fastForward(branch: String, fromRemote remote: String, branch remoteBranch: String) async throws {
        Logger.gitRepository.info("Fast-forwarding \(branch, privacy: .public) from \(remote, privacy: .public)/\(remoteBranch, privacy: .public)")
        try await shell.run(["fetch", remote, "refs/heads/\(remoteBranch):refs/heads/\(branch)"])
    }

    /// Pushes local `branch` (checked out or not) to `remoteBranch` on `remote`; `setUpstream` makes it track that.
    public func push(branch: String, to remote: String, as remoteBranch: String, setUpstream: Bool) async throws {
        Logger.gitRepository.info("Pushing \(branch, privacy: .public) to \(remote, privacy: .public)/\(remoteBranch, privacy: .public)")
        try await shell.run(["push"] + (setUpstream ? ["-u"] : []) + [remote, "refs/heads/\(branch):refs/heads/\(remoteBranch)"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }
}
