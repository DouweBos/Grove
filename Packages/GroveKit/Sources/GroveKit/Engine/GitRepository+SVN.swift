// Engine/GitRepository+SVN.swift
// GroveKit
//
// git-svn: detecting a Subversion-backed clone, fetching and rebasing from it, and dcommitting to it.

import Foundation
import os

enum SVNError: LocalizedError {
    case notInstalled

    var errorDescription: String? { SVNStatus.missingMessage }
}

/// Finds a git that has git-svn; Apple's /usr/bin/git doesn't, Homebrew's does once subversion is installed.
/// Only runners that can switch executables (the local one) offer git-svn.
public nonisolated enum SVNSupport {
    static let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]

    /// A found path is kept; a miss is re-checked after a minute, so installing git-svn is picked up.
    private static let lookup = OSAllocatedUnfairLock<(path: String?, checked: Date?)>(initialState: (nil, nil))

    static func gitPath(using runner: any GitRunner) async -> String? {
        let cached = lookup.withLock { $0 }
        if let path = cached.path { return path }
        if let checked = cached.checked, Date().timeIntervalSince(checked) < 60 { return nil }
        var found: String?
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            guard let svnRunner = runner.withGitExecutable(path) else { return nil }
            let shell = GitShell(workingDirectory: FileManager.default.temporaryDirectory, runner: svnRunner)
            if (try? await shell.runAllowingFailure(["svn", "--version"]))?.isSuccess == true {
                found = path
                break
            }
        }
        lookup.withLock { $0 = (found, Date()) }
        return found
    }

    public static func shell(in directory: URL, runner: any GitRunner) async throws -> GitShell {
        guard let path = await gitPath(using: runner), let svnRunner = runner.withGitExecutable(path) else { throw SVNError.notInstalled }
        return GitShell(workingDirectory: directory, runner: svnRunner)
    }
}

extension GitRepository {

    public func svnStatus() async -> SVNStatus {
        let result = try? await shell.runAllowingFailure(["config", "--get-regexp", "^svn-remote\\."])
        var status = SVNStatus(configValues: Self.parseConfigList(result?.stdout ?? ""))
        guard status.isSVN else { return status }
        status.isAvailable = await SVNSupport.gitPath(using: shell.runner) != nil
        if let ref = status.trackingRef,
           let count = try? await shell.runAllowingFailure(["rev-list", "--count", "\(ref)..HEAD"]), count.isSuccess {
            status.unsentCount = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return status
    }

    /// `git svn rebase` fetches and replays local commits on top; `rebase: false` only fetches.
    public func svnFetch(rebase: Bool) async throws {
        Logger.gitRepository.info("git svn \(rebase ? "rebase" : "fetch", privacy: .public) in \(self.displayName, privacy: .public)")
        try await SVNSupport.shell(in: path, runner: shell.runner).run(["svn", rebase ? "rebase" : "fetch"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
    }

    /// Sends each local commit to Subversion as a revision, then rewrites them with their svn metadata.
    public func svnDcommit() async throws {
        Logger.gitRepository.info("git svn dcommit in \(self.displayName, privacy: .public)")
        try await SVNSupport.shell(in: path, runner: shell.runner).run(["svn", "dcommit"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
    }
}
