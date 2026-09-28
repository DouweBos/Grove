// Mocks/MockGitRepository.swift
// Grove
//
// Realistic in-memory fake that conforms to GitRepositoryProtocol.
// Used by ALL view agents during Phase B development and in SwiftUI Previews.
// All methods simulate async latency with a brief Task.sleep.

import Foundation
import Observation

// MARK: - MockGitRepository

/// An in-memory fake Git repository with realistic static data.
///
/// Every ``GitRepositoryProtocol`` method returns pre-baked fake data after a
/// short artificial delay to surface any loading-state UI issues early.
@MainActor
@Observable
final class MockGitRepository: GitRepositoryProtocol {

    // MARK: Observable State

    let path: URL
    let displayName: String
    var currentBranch: BranchInfo?
    var repositoryState: RepositoryState = .normal

    // MARK: Init

    init(
        path: URL = URL(fileURLWithPath: "/Users/dev/Projects/my-app"),
        displayName: String = "my-app"
    ) {
        self.path = path
        self.displayName = displayName
        self.currentBranch = MockData.branches.first(where: { $0.isHEAD })
    }

    // MARK: Helpers

    /// How often each git call ran, keyed by its signature, e.g. `"tags()"`; tests check for cache hits and duplicate reads.
    @ObservationIgnored private(set) var callCounts: [String: Int] = [:]

    func recordCall(_ name: String = #function) {
        callCounts[name, default: 0] += 1
    }

    /// Simulates a realistic async round-trip (50 ms by default).
    func simulateLatency(_ nanoseconds: UInt64 = 50_000_000, caller: String = #function) async {
        recordCall(caller)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: Status

    func refreshStatus() async throws {
        await simulateLatency()
    }

    func status() async throws -> [StatusEntry] {
        await simulateLatency()
        return MockData.statusEntries
    }

    func listTrackedFiles() async throws -> [String] {
        await simulateLatency()
        return MockData.trackedFiles
    }

    // MARK: Staging

    func stage(paths: [String]) async throws {
        await simulateLatency()
    }

    func unstage(paths: [String]) async throws {
        await simulateLatency()
    }

    func stageHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    func unstageHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    func stageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    func unstageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    func discardLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    func stageAll() async throws {
        await simulateLatency()
    }

    func unstageAll() async throws {
        await simulateLatency()
    }

    func discardChanges(paths: [String]) async throws {
        await simulateLatency()
    }

    func discardHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    // MARK: Diff

    func diff(for entry: StatusEntry, staged: Bool, ignoreWhitespace: Bool = false) async throws -> DiffResult {
        await simulateLatency()
        return MockData.diffResult(for: entry.path)
    }

    func diffForCommit(_ sha: String) async throws -> [FileDiff] {
        await simulateLatency()
        return MockData.commitFileDiffs
    }

    func filesInCommit(_ sha: String) async throws -> [String] {
        await simulateLatency()
        return MockData.trackedFiles
    }

    // MARK: Commits

    @discardableResult
    func commit(message: String, body: String?, amend: Bool, sign: Bool = false) async throws -> CommitInfo {
        await simulateLatency()
        return MockData.commits[0]
    }

    func isSigningConfigured() async throws -> Bool {
        await simulateLatency()
        return true
    }

    func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo] {
        await simulateLatency(30_000_000)
        let all = MockData.commits
        let start = min(skip, all.count)
        let end = min(start + maxCount, all.count)
        return Array(all[start..<end])
    }

    func fileLog(path: String, maxCount: Int) async throws -> [CommitInfo] {
        await simulateLatency(60_000_000)
        // Return a plausible subset of commits to simulate file-specific history.
        return Array(MockData.commits.prefix(maxCount))
    }

    func commitDetail(_ sha: String) async throws -> CommitInfo {
        await simulateLatency()
        return MockData.commits.first(where: { $0.id == sha }) ?? MockData.commits[0]
    }

    // MARK: Branches

    func localBranches() async throws -> [BranchInfo] {
        await simulateLatency()
        return MockData.branches.filter(\.isLocal)
    }

    func remoteBranches() async throws -> [BranchInfo] {
        await simulateLatency()
        return MockData.branches.filter(\.isRemote)
    }

    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo {
        await simulateLatency()
        let branch = BranchInfo(
            id: "refs/heads/\(name)",
            name: name,
            isLocal: true,
            isRemote: false,
            isHEAD: checkout,
            targetSHA: MockData.commits[0].id,
            remoteName: nil,
            upstream: nil,
            ahead: 0,
            behind: 0
        )
        if checkout {
            currentBranch = branch
        }
        return branch
    }

    func checkout(branch: String) async throws {
        await simulateLatency(80_000_000)
        currentBranch = MockData.branches.first(where: { $0.name == branch })
    }

    func deleteBranch(name: String, force: Bool) async throws {
        await simulateLatency()
    }

    func deleteRemoteBranch(name: String, remote: String) async throws {
        await simulateLatency()
    }

    func renameBranch(oldName: String, newName: String) async throws {
        await simulateLatency()
    }

    // MARK: Remotes

    func remotes() async throws -> [RemoteInfo] {
        await simulateLatency()
        return MockData.remotes
    }

    func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(200_000_000)
        progress?(1.0)
    }

    func pull(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    func pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    func push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    func push(remote: String?, forceWithLease: Bool, setUpstream: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    func sync(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(200_000_000)
        progress?(0.33)
        await simulateLatency(200_000_000)
        progress?(0.66)
        await simulateLatency(200_000_000)
        progress?(1.0)
    }

    // MARK: Merge / Rebase

    func merge(branch: String) async throws {
        await simulateLatency(150_000_000)
    }

    func abortMerge() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    func rebase(onto: String) async throws {
        await simulateLatency(150_000_000)
    }

    func abortRebase() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    func continueRebase() async throws {
        await simulateLatency()
    }

    func conflicts() async throws -> [StatusEntry] {
        await simulateLatency()
        return MockData.statusEntries.filter { $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted }
    }

    // MARK: Cherry-pick

    func cherryPick(commit: String) async throws {
        await simulateLatency(100_000_000)
    }

    func abortCherryPick() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    // MARK: Revert

    func revert(commit: String) async throws {
        await simulateLatency(100_000_000)
    }

    func abortRevert() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    // MARK: Bisect

    func bisectStart() async throws {
        await simulateLatency()
        repositoryState = .bisect
    }

    func bisectBad(commit: String?) async throws {
        await simulateLatency()
    }

    func bisectGood(commit: String?) async throws {
        await simulateLatency()
    }

    func bisectReset() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    func bisectLog() async throws -> [String] {
        await simulateLatency()
        return [
            "# bad: [a1b2c3d] feat: add OAuth2 authentication flow",
            "# good: [86a1b2c] chore: initial project scaffold",
            "git bisect bad a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            "git bisect good 86a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"
        ]
    }

    // MARK: Interactive Rebase

    func rebaseInteractive(onto: String, commitCount: Int) async throws {
        await simulateLatency(150_000_000)
    }

    func squashCommits(_ commits: [String], message: String) async throws {
        await simulateLatency(200_000_000)
    }

    func rewordCommit(_ commit: String, newMessage: String) async throws {
        await simulateLatency(150_000_000)
    }

    func dropCommit(_ commit: String) async throws {
        await simulateLatency(150_000_000)
    }

    // MARK: Reset

    func resetToCommit(_ commit: String, mode: ResetMode) async throws {
        await simulateLatency(100_000_000)
        currentBranch = MockData.branches.first(where: { $0.isHEAD })
    }

    // MARK: Clean

    func cleanUntracked(directories: Bool, force: Bool) async throws {
        await simulateLatency()
    }

    // MARK: Stash

    func stashes() async throws -> [StashEntry] {
        await simulateLatency()
        return MockData.stashEntries
    }

    func stashCreate(message: String?, includeUntracked: Bool, paths: [String]? = nil) async throws {
        await simulateLatency()
    }

    func stashApply(index: Int, drop: Bool) async throws {
        await simulateLatency()
    }

    func stashDrop(index: Int) async throws {
        await simulateLatency()
    }

    // MARK: Tags

    func tags() async throws -> [TagInfo] {
        await simulateLatency()
        return MockData.tags
    }

    @discardableResult
    func createTag(name: String, at sha: String?, message: String?, sign: Bool = false) async throws -> TagInfo {
        await simulateLatency()
        return TagInfo(
            id: name,
            name: name,
            targetSHA: sha ?? MockData.commits[0].id,
            isAnnotated: message != nil || sign,
            message: message,
            taggerName: "Jane Developer",
            taggerDate: Date()
        )
    }

    func deleteTag(name: String) async throws {
        await simulateLatency()
    }

    func pushTag(name: String, remote: String?) async throws {
        await simulateLatency(150_000_000)
    }

    func pushAllTags(remote: String?) async throws {
        await simulateLatency(200_000_000)
    }

    // MARK: Submodules

    func updateSubmodule(path: String) async throws {
        await simulateLatency()
    }

    func submodules() async throws -> [SubmoduleInfo] {
        [
            SubmoduleInfo(name: "vendor/analytics", path: "vendor/analytics", url: "https://github.com/example/analytics.git",
                          sha: "1a2b3c4d5e6f7a8b9c0d", state: .upToDate),
            SubmoduleInfo(name: "vendor/icons", path: "vendor/icons", url: "https://github.com/example/icons.git",
                          sha: "9f8e7d6c5b4a39281706", state: .uninitialized)
        ]
    }

    // MARK: Worktrees

    func worktrees() async throws -> [WorktreeInfo] {
        [
            WorktreeInfo(path: path.path, branch: "main", headSHA: "a1b2c3d4e5f6", isMain: true, isPrunable: false, isLocked: false),
            WorktreeInfo(path: path.path + "-feature-auth", branch: "feature/auth", headSHA: "b2c3d4e5f6a1",
                         isMain: false, isPrunable: false, isLocked: false)
        ]
    }

    func removeWorktree(path: String, force: Bool) async throws {
        await simulateLatency()
    }

    // MARK: Working Copy

    func commitIdentity() async -> CommitIdentity? {
        CommitIdentity(name: "Jane Developer", email: "jane@example.com")
    }

    func operationContext() async -> OperationContext? {
        repositoryState == .normal ? nil : OperationContext(oursLabel: currentBranch?.name ?? "main", theirsLabel: "feature/auth")
    }

    func continueOperation() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    func conflictVersions(path: String) async throws -> ConflictVersions {
        ConflictVersions(ours: "let value = 1\n", theirs: "let value = 2\n")
    }
}
