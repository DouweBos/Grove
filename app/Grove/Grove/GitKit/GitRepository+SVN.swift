// GitKit/GitRepository+SVN.swift
// Grove
//
// git-svn: detecting a Subversion-backed clone, fetching and rebasing from it, and dcommitting to it.

import Foundation
import os

enum SVNError: LocalizedError {
    case notInstalled

    var errorDescription: String? { SVNStatus.missingMessage }
}

/// Finds a git that has git-svn; Apple's /usr/bin/git doesn't, Homebrew's does once subversion is installed.
nonisolated enum SVNSupport {
    static let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]

    /// A found path is kept; a miss is re-checked after a minute, so installing git-svn is picked up.
    private static let lookup = OSAllocatedUnfairLock<(path: String?, checked: Date?)>(initialState: (nil, nil))

    static func gitPath() async -> String? {
        let cached = lookup.withLock { $0 }
        if let path = cached.path { return path }
        if let checked = cached.checked, Date().timeIntervalSince(checked) < 60 { return nil }
        var found: String?
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let shell = GitShell(workingDirectory: FileManager.default.temporaryDirectory, gitPath: path)
            if (try? await shell.runAllowingFailure(["svn", "--version"]))?.isSuccess == true {
                found = path
                break
            }
        }
        lookup.withLock { $0 = (found, Date()) }
        return found
    }

    static func shell(in directory: URL) async throws -> GitShell {
        guard let path = await gitPath() else { throw SVNError.notInstalled }
        return GitShell(workingDirectory: directory, gitPath: path)
    }
}

extension GitRepository {

    func svnStatus() async -> SVNStatus {
        let result = try? await shell.runAllowingFailure(["config", "--get-regexp", "^svn-remote\\."])
        var status = SVNStatus(configValues: Self.parseConfigList(result?.stdout ?? ""))
        guard status.isSVN else { return status }
        status.isAvailable = await SVNSupport.gitPath() != nil
        if let ref = status.trackingRef,
           let count = try? await shell.runAllowingFailure(["rev-list", "--count", "\(ref)..HEAD"]), count.isSuccess {
            status.unsentCount = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return status
    }

    /// `git svn rebase` fetches and replays local commits on top; `rebase: false` only fetches.
    func svnFetch(rebase: Bool) async throws {
        Logger.gitRepository.info("git svn \(rebase ? "rebase" : "fetch", privacy: .public) in \(self.displayName, privacy: .public)")
        try await SVNSupport.shell(in: path).run(["svn", rebase ? "rebase" : "fetch"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    /// Sends each local commit to Subversion as a revision, then rewrites them with their svn metadata.
    func svnDcommit() async throws {
        Logger.gitRepository.info("git svn dcommit in \(self.displayName, privacy: .public)")
        try await SVNSupport.shell(in: path).run(["svn", "dcommit"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }
}
