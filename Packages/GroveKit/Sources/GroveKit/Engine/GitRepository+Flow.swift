// Engine/GitRepository+Flow.swift
// GroveKit
//
// git-flow done with plain git: the `gitflow.*` config, then branch, merge --no-ff and tag, as git-flow would.

import Foundation
import os

enum GitFlowError: LocalizedError {
    case noCommits
    case invalidName(String)
    case branchExists(String)
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .noCommits: "git-flow needs at least one commit on the production branch."
        case .invalidName(let name): "\u{201C}\(name)\u{201D} isn't a valid branch name."
        case .branchExists(let name): "A branch named \u{201C}\(name)\u{201D} already exists."
        case .notInitialized: "git-flow isn't set up in this repository."
        }
    }
}

extension GitRepository {

    public func gitFlowConfig() async -> GitFlowConfig? {
        let result = try? await shell.runAllowingFailure(["config", "--local", "--get-regexp", "^gitflow\\."])
        return GitFlowConfig(configValues: Self.parseConfigList(result?.stdout ?? ""))
    }

    /// Writes the config, creates develop from production when missing, and checks develop out.
    public func initializeGitFlow(_ config: GitFlowConfig) async throws {
        guard try await branchExists(config.productionBranch) else { throw GitFlowError.noCommits }
        for (key, value) in config.configValues {
            try await shell.run(["config", "--local", key, value])
        }
        if try await !branchExists(config.developBranch) {
            try await shell.run(["branch", "--no-track", config.developBranch, config.productionBranch])
        }
        try await shell.run(["checkout", "-q", config.developBranch])
        await reloadHead()
    }

    public func startFlowBranch(_ kind: GitFlowKind, name: String, base: String?, config: GitFlowConfig) async throws {
        let branch = config.branchName(kind, name)
        try await validateNewBranch(branch)
        Logger.gitRepository.info("git-flow: starting \(branch, privacy: .public)")
        try await shell.run(["checkout", "-q", "-b", branch, base ?? config.base(for: kind)])
        await reloadHead()
    }

    /// Features merge into develop; releases and hotfixes into production (tagged) and back into develop,
    /// or into a release in progress for a hotfix, as git-flow does. Conflicts stop on the branch being merged into.
    public func finishFlowBranch(_ kind: GitFlowKind, name: String, config: GitFlowConfig, options: GitFlowFinishOptions) async throws {
        let branch = config.branchName(kind, name)
        Logger.gitRepository.info("git-flow: finishing \(branch, privacy: .public)")
        do {
            try await finishSteps(kind, branch: branch, name: name, config: config, options: options)
        } catch {
            await reloadHead()
            throw error
        }
        await reloadHead()
    }

    private func finishSteps(_ kind: GitFlowKind, branch: String, name: String, config: GitFlowConfig,
                             options: GitFlowFinishOptions) async throws {
        if kind == .feature {
            try await mergeFlowBranch(branch, into: config.developBranch, squash: options.squash)
        } else {
            try await mergeFlowBranch(branch, into: config.productionBranch, squash: false)
            if let message = options.tagMessage {
                try await shell.run(["tag", "-a", config.versionTagPrefix + name, "-m", message])
            }
            let backInto = kind == .hotfix ? try await releaseInProgress(config) ?? config.developBranch : config.developBranch
            try await mergeFlowBranch(branch, into: backInto, squash: false)
        }
        if !options.keepBranch {
            // Squashed branches aren't merged in git's eyes, so they need -D.
            try await shell.run(["branch", options.squash ? "-D" : "-d", branch])
        }
        if options.push {
            try await shell.run(["push", "origin", config.developBranch, config.productionBranch, "--follow-tags"])
        }
    }

    // MARK: Helpers

    private func mergeFlowBranch(_ branch: String, into target: String, squash: Bool) async throws {
        try await shell.run(["checkout", "-q", target])
        if squash {
            try await shell.run(["merge", "--squash", branch])
            try await shell.run(["commit", "-q", "-m", "Merge branch '\(branch)' into \(target) (squashed)"])
        } else {
            try await shell.run(["merge", "--no-ff", "-m", "Merge branch '\(branch)' into \(target)", branch])
        }
    }

    private func releaseInProgress(_ config: GitFlowConfig) async throws -> String? {
        let result = try await shell.run(["for-each-ref", "--format=%(refname:short)", "refs/heads/\(config.releasePrefix)"])
        return result.stdout.split(separator: "\n").first.map(String.init)
    }

    private func validateNewBranch(_ branch: String) async throws {
        guard try await shell.runAllowingFailure(["check-ref-format", "--branch", branch]).isSuccess else {
            throw GitFlowError.invalidName(branch)
        }
        if try await branchExists(branch) { throw GitFlowError.branchExists(branch) }
    }

    private func branchExists(_ name: String) async throws -> Bool {
        try await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "refs/heads/\(name)"]).isSuccess
    }

    private func reloadHead() async {
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
    }

    /// `git config --get-regexp` prints `key value` per line; values may be empty.
    nonisolated static func parseConfigList(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first else { continue }
            values[String(key)] = parts.count > 1 ? String(parts[1]) : ""
        }
        return values
    }
}
