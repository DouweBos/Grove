// Engine/GitRepository+Refs.swift
// GroveKit
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
        try await createBranch(name: name, from: from, checkout: checkout, track: false, parent: nil)
    }

    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool, track: Bool, parent: String?) async throws -> BranchInfo {
        var args = checkout ? ["checkout", "-b", name] : ["branch", name]
        if track { args.append("--track") }
        if let from { args.append(from) }
        try await shell.run(args)
        if let parent, !parent.isEmpty {
            try await shell.run(["config", "--local", Self.parentConfigKey(for: name), parent])
        }

        let branches = try await localBranches()
        guard let branch = branches.first(where: { $0.name == name }) else {
            throw GitRepositoryError.branchNotFound(name)
        }

        if checkout {
            currentBranch = branch
        }
        return branch
    }

    /// Parent recorded for each branch created with one, from a single config read.
    func branchParents() async throws -> [String: String] {
        let result = try await shell.runAllowingFailure(["config", "--local", "--get-regexp", #"^branch\..*\.grove-parent$"#])
        // Exit 1 just means no branch has a parent yet.
        guard result.isSuccess else { return [:] }
        return Self.parseBranchParents(result.stdout)
    }

    nonisolated static func parentConfigKey(for branch: String) -> String { "branch.\(branch).grove-parent" }

    /// `branch.feature/x.grove-parent main` lines → ["feature/x": "main"].
    nonisolated static func parseBranchParents(_ output: String) -> [String: String] {
        var parents: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("branch."), parts[0].hasSuffix(".grove-parent") else { continue }
            let branch = parts[0].dropFirst("branch.".count).dropLast(".grove-parent".count)
            parents[String(branch)] = parts[1]
        }
        return parents
    }

    func checkout(branch: String) async throws {
        try await shell.run(["checkout", branch])
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
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

    func setUpstream(of branch: String, to remoteBranch: String?) async throws {
        if let remoteBranch {
            try await shell.run(["branch", "--set-upstream-to=\(remoteBranch)", branch])
        } else {
            try await shell.run(["branch", "--unset-upstream", branch])
        }
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

    func pull(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws {
        try await pull(remote: remote, branch: nil, strategy: strategy, options: PullOptions(), progress: progress)
    }

    func defaultPullStrategy() async -> PullStrategy {
        if let rebase = await configValue("pull.rebase")?.lowercased(), rebase != "false" { return .rebase }
        return await configValue("pull.ff")?.lowercased() == "only" ? .fastForwardOnly : .merge
    }

    func pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        Logger.gitRepository.info(
            "Pulling (\(strategy.rawValue, privacy: .public)) from \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["pull"]
        switch strategy {
        // `--ff` overrides `pull.ff=only` so a diverged branch still gets a merge commit.
        case .merge: args += ["--no-rebase", "--ff"]
        case .rebase: args.append("--rebase")
        case .fastForwardOnly: args.append("--ff-only")
        }
        if options.verifySignatures { args.append("--verify-signatures") }
        if options.skipHooks { args.append("--no-verify") }
        if let remote { args.append(remote) }
        if let branch { args.append(branch) }
        try await shell.run(args)
        progress?(0.8)
        try await pullLFSObjectsIfNeeded(remote: remote)
        progress?(1.0)
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        let previousState = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
        Logger.gitRepository.info("Pull complete in \(self.displayName, privacy: .public)")
        if repositoryState != previousState {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after pull: \(previousState.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func push(remote: String?, forceWithLease: Bool, setUpstream: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let flags = (forceWithLease ? " --force-with-lease" : "") + (setUpstream ? " -u" : "")
        Logger.gitRepository.info(
            "Pushing\(flags, privacy: .public) to \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["push"]
        if forceWithLease { args.append("--force-with-lease") }
        let upstreamRemote = (try? await Self.loadCurrentBranch(shell: shell))?.upstreamRemoteName
        if setUpstream {
            args += ["-u", remote ?? upstreamRemote ?? "origin", "HEAD"]
        } else if let remote, remote != upstreamRemote {
            // An explicit refspec lets untracked branches and other remotes push without `push.default` guessing.
            args += [remote, "HEAD"]
        } else if let remote {
            args.append(remote)
        }
        try await shell.run(args)
        progress?(1.0)
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Push complete in \(self.displayName, privacy: .public)")
    }

    func push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        Logger.gitRepository.info(
            "Pushing to \(remote, privacy: .public)/\(branch, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["push"]
        if forceWithLease { args.append("--force-with-lease") }
        if setUpstream { args.append("-u") }
        if let mode = options.recurseSubmodules { args.append("--recurse-submodules=\(mode.rawValue)") }
        if options.skipHooks { args.append("--no-verify") }
        args += [remote, "HEAD:refs/heads/\(branch)"]
        try await shell.run(args)
        progress?(1.0)
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Push complete in \(self.displayName, privacy: .public)")
    }

    func publishBranch(_ name: String, to remote: String, as target: String) async throws {
        Logger.gitRepository.info("Publishing \(name, privacy: .public) to \(remote, privacy: .public) in \(self.displayName, privacy: .public)")
        try await shell.run(["push", "-u", remote, "refs/heads/\(name):refs/heads/\(target)"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }

    func defaultBranch(of remote: String) async -> String? {
        guard let result = try? await shell.runAllowingFailure(["symbolic-ref", "--quiet", "--short", "refs/remotes/\(remote)/HEAD"]),
              result.isSuccess else { return nil }
        let short = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return short.hasPrefix(remote + "/") ? String(short.dropFirst(remote.count + 1)) : nil
    }

    func sync(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws {
        Logger.gitRepository.info(
            "Syncing with \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await fetch(remote: remote, progress: nil)
        progress?(0.33)
        let branch = try? await Self.loadCurrentBranch(shell: shell)
        let target = remote ?? branch?.upstreamRemoteName ?? "origin"
        let tracksTarget = branch?.upstream != nil && branch?.upstreamRemoteName == target
        if tracksTarget {
            try await pull(remote: nil, branch: nil, strategy: strategy, options: PullOptions(), progress: nil)
        } else if let name = branch?.name,
                  try await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "refs/remotes/\(target)/\(name)"]).isSuccess {
            try await pull(remote: target, branch: name, strategy: strategy, options: PullOptions(), progress: nil)
        }
        progress?(0.66)
        try await push(remote: target, forceWithLease: false, setUpstream: !tracksTarget, progress: nil)
        progress?(1.0)
        Logger.gitRepository.info("Sync complete in \(self.displayName, privacy: .public)")
    }

    // MARK: - Tags

    func tags() async throws -> [TagInfo] {
        let result = try await shell.run([
            "for-each-ref",
            "--sort=-creatordate",
            "--format=%(refname:short)%00%(objectname)%00%(objecttype)%00%(*objectname)%00%(contents:subject)%00%(taggername)%00%(taggerdate:iso-strict)",
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
