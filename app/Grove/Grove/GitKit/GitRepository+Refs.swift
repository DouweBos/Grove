// GitKit/GitRepository+Refs.swift
// Grove
//
// Branches, remotes and tags.

import Foundation
import os

extension GitRepository {

    // MARK: - Branches

    func localBranches() async throws -> [BranchInfo] {
        try await fetchBranches(refPattern: "refs/heads/")
    }

    func remoteBranches() async throws -> [BranchInfo] {
        try await fetchBranches(refPattern: "refs/remotes/")
    }

    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo {
        var args: [String]
        if checkout {
            args = ["checkout", "-b", name]
            if let from { args.append(from) }
        } else {
            args = ["branch", name]
            if let from { args.append(from) }
        }
        try await shell.run(args)

        let branches = try await localBranches()
        guard let branch = branches.first(where: { $0.name == name }) else {
            throw GitRepositoryError.branchNotFound(name)
        }

        if checkout {
            currentBranch = branch
        }
        return branch
    }

    func checkout(branch: String) async throws {
        try await shell.run(["checkout", branch])
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func deleteBranch(name: String, force: Bool) async throws {
        let flag = force ? "-D" : "-d"
        try await shell.run(["branch", flag, name])
    }

    func deleteRemoteBranch(name: String, remote: String) async throws {
        try await shell.run(["push", remote, "--delete", name])
    }

    func renameBranch(oldName: String, newName: String) async throws {
        try await shell.run(["branch", "-m", oldName, newName])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }

    // MARK: - Remotes

    func remotes() async throws -> [RemoteInfo] {
        let result = try await shell.run(["remote", "-v"])
        return parseRemoteVerbose(result.stdout)
    }

    func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws {
        Logger.gitRepository.info(
            "Fetching \(remote ?? "all remotes", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["fetch", "--prune"]
        if let remote { args.append(remote) }
        try await shell.run(args)
        progress?(1.0)
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Fetch complete in \(self.displayName, privacy: .public)")
    }

    func pull(remote: String?, rebase: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let strategy = rebase ? "rebase" : "merge"
        Logger.gitRepository.info(
            "Pulling (\(strategy, privacy: .public)) from \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["pull"]
        if rebase { args.append("--rebase") }
        if let remote { args.append(remote) }
        try await shell.run(args)
        progress?(1.0)
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        let previousState = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        Logger.gitRepository.info("Pull complete in \(self.displayName, privacy: .public)")
        if repositoryState != previousState {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after pull: \(previousState.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func push(remote: String?, force: Bool, forceWithLease: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let forceDescription = forceWithLease ? " --force-with-lease" : (force ? " --force" : "")
        Logger.gitRepository.info(
            "Pushing\(forceDescription, privacy: .public) to \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["push"]
        if forceWithLease {
            args.append("--force-with-lease")
        } else if force {
            args.append("--force")
        }
        if let remote { args.append(remote) }
        try await shell.run(args)
        progress?(1.0)
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Push complete in \(self.displayName, privacy: .public)")
    }

    func sync(remote: String?, rebase: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        Logger.gitRepository.info(
            "Syncing with \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await fetch(remote: remote, progress: nil)
        progress?(0.33)
        try await pull(remote: remote, rebase: rebase, progress: nil)
        progress?(0.66)
        try await push(remote: remote, force: false, forceWithLease: false, progress: nil)
        progress?(1.0)
        Logger.gitRepository.info("Sync complete in \(self.displayName, privacy: .public)")
    }

    // MARK: - Tags

    func tags() async throws -> [TagInfo] {
        let result = try await shell.run([
            "for-each-ref",
            "--sort=-creatordate",
            "--format=%(refname:short)%00%(objectname:short)%00%(objecttype)%00%(*objectname:short)%00%(contents:subject)%00%(taggername)%00%(taggerdate:iso-strict)",
            "refs/tags/"
        ])
        return parseTagList(result.stdout)
    }

    @discardableResult
    func createTag(name: String, at sha: String?, message: String?, sign: Bool = false) async throws -> TagInfo {
        var args: [String]
        if sign {
            // -s implies an annotated tag and uses the configured signing key.
            args = ["tag", "-s", name]
            if let message { args += ["-m", message] }
        } else if let message {
            args = ["tag", "-a", name, "-m", message]
        } else {
            args = ["tag", name]
        }
        if let sha { args.append(sha) }
        try await shell.run(args)

        let allTags = try await tags()
        guard let tag = allTags.first(where: { $0.name == name }) else {
            throw GitRepositoryError.tagNotFound(name)
        }
        return tag
    }

    func deleteTag(name: String) async throws {
        try await shell.run(["tag", "-d", name])
    }

    func pushTag(name: String, remote: String?) async throws {
        let remoteName = remote ?? "origin"
        Logger.gitRepository.info(
            "Pushing tag '\(name, privacy: .public)' to \(remoteName, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["push", remoteName, "refs/tags/\(name)"])
        Logger.gitRepository.info("Tag push complete in \(self.displayName, privacy: .public)")
    }

    func pushAllTags(remote: String?) async throws {
        let remoteName = remote ?? "origin"
        Logger.gitRepository.info(
            "Pushing all tags to \(remoteName, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["push", remoteName, "--tags"])
        Logger.gitRepository.info("All tags pushed in \(self.displayName, privacy: .public)")
    }
}
