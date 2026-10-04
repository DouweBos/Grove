// Mocks/MockGitRepository.swift
// GroveKit
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
public final class MockGitRepository: GitRepositoryProtocol {

    // MARK: Observable State

    public let path: URL
    public let displayName: String
    public var currentBranch: BranchInfo?
    public var repositoryState: RepositoryState = .normal

    // MARK: Init

    public init(
        path: URL = URL(fileURLWithPath: "/Users/dev/Projects/my-app"),
        displayName: String = "my-app"
    ) {
        self.path = path
        self.displayName = displayName
        self.currentBranch = MockData.branches.first(where: { $0.isHEAD })
    }

    // MARK: Helpers

    /// How often each git call ran, keyed by its signature, e.g. `"tags()"`; tests check for cache hits and duplicate reads.
    @ObservationIgnored public private(set) var callCounts: [String: Int] = [:]
    @ObservationIgnored public var ci = MockCIState()

    func recordCall(_ name: String = #function) {
        callCounts[name, default: 0] += 1
    }

    /// Simulates a realistic async round-trip (50 ms by default).
    func simulateLatency(_ nanoseconds: UInt64 = 50_000_000, caller: String = #function) async {
        recordCall(caller)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: Status

    public func refreshStatus() async throws {
        await simulateLatency()
    }

    public func status() async throws -> [StatusEntry] {
        await simulateLatency()
        return MockData.statusEntries
    }

    public func listTrackedFiles() async throws -> [String] {
        await simulateLatency()
        return MockData.trackedFiles
    }

    // MARK: Staging

    public func stage(paths: [String]) async throws {
        await simulateLatency()
    }

    public func unstage(paths: [String]) async throws {
        await simulateLatency()
    }

    public func stageHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    public func unstageHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    public func stageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    public func unstageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    public func discardLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    public func stageAll() async throws {
        await simulateLatency()
    }

    public func unstageAll() async throws {
        await simulateLatency()
    }

    public func discardChanges(paths: [String]) async throws {
        await simulateLatency()
    }

    public func discardHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    // MARK: Diff

    public func diff(for entry: StatusEntry, staged: Bool, ignoreWhitespace: Bool = false) async throws -> DiffResult {
        await simulateLatency()
        return MockData.diffResult(for: entry.path)
    }

    public func diffForCommit(_ sha: String) async throws -> [FileDiff] {
        await simulateLatency()
        return MockData.commitFileDiffs
    }

    public func diff(from: String, to: String) async throws -> [FileDiff] {
        await simulateLatency()
        return MockData.commitFileDiffs
    }

    public func filesInCommit(_ sha: String) async throws -> [String] {
        await simulateLatency()
        return MockData.trackedFiles
    }

    // MARK: Commits

    @discardableResult
    public func commit(message: String, body: String?, amend: Bool, sign: Bool = false) async throws -> CommitInfo {
        await simulateLatency()
        return MockData.commits[0]
    }

    public func isSigningConfigured() async throws -> Bool {
        await simulateLatency()
        return true
    }

    public func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo] {
        await simulateLatency(30_000_000)
        let all = MockData.commits
        let start = min(skip, all.count)
        let end = min(start + maxCount, all.count)
        return Array(all[start..<end])
    }

    public func fileLog(path: String, maxCount: Int) async throws -> [CommitInfo] {
        await simulateLatency(60_000_000)
        // Return a plausible subset of commits to simulate file-specific history.
        return Array(MockData.commits.prefix(maxCount))
    }

    public func commitDetail(_ sha: String) async throws -> CommitInfo {
        await simulateLatency()
        return MockData.commits.first(where: { $0.id == sha }) ?? MockData.commits[0]
    }

    public func isAncestor(_ commit: String, of descendant: String) async -> Bool {
        MockData.commits.contains { $0.id == commit }
    }

    public func formatPatch(commits: [String]) async throws -> String {
        commits.map { "From \($0) Mon Sep 17 00:00:00 2001\n" }.joined()
    }

    public func archive(revision: String, to url: URL) async throws {
        try Data().write(to: url)
    }

    // MARK: Branches

    public func localBranches() async throws -> [BranchInfo] {
        await simulateLatency()
        return MockData.branches.filter(\.isLocal)
    }

    public func remoteBranches() async throws -> [BranchInfo] {
        await simulateLatency()
        return MockData.branches.filter(\.isRemote)
    }

    @discardableResult
    public func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo {
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

    public func checkout(branch: String) async throws {
        await simulateLatency(80_000_000)
        currentBranch = MockData.branches.first(where: { $0.name == branch })
    }

    public func deleteBranch(name: String, force: Bool) async throws {
        await simulateLatency()
    }

    public func deleteRemoteBranch(name: String, remote: String) async throws {
        await simulateLatency()
    }

    public func renameBranch(oldName: String, newName: String) async throws {
        await simulateLatency()
    }

    // MARK: Remotes

    public func remotes() async throws -> [RemoteInfo] {
        await simulateLatency()
        return MockData.remotes
    }

    public func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(200_000_000)
        progress?(1.0)
    }

    public func pull(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    public func pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    public func push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    public func push(remote: String?, forceWithLease: Bool, setUpstream: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    public func sync(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(200_000_000)
        progress?(0.33)
        await simulateLatency(200_000_000)
        progress?(0.66)
        await simulateLatency(200_000_000)
        progress?(1.0)
    }

    // MARK: Merge / Rebase

    public func merge(branch: String) async throws {
        await simulateLatency(150_000_000)
    }

    public func abortMerge() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    public func rebase(onto: String) async throws {
        await simulateLatency(150_000_000)
    }

    public func abortRebase() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    public func continueRebase() async throws {
        await simulateLatency()
    }

    public func conflicts() async throws -> [StatusEntry] {
        await simulateLatency()
        return MockData.statusEntries.filter { $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted }
    }

    // MARK: Cherry-pick

    public func cherryPick(commit: String) async throws {
        await simulateLatency(100_000_000)
    }

    public func abortCherryPick() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    // MARK: Revert

    public func revert(commit: String) async throws {
        await simulateLatency(100_000_000)
    }

    public func abortRevert() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    // MARK: Bisect

    public func bisectStart() async throws {
        await simulateLatency()
        repositoryState = .bisect
    }

    public func bisectBad(commit: String?) async throws {
        await simulateLatency()
    }

    public func bisectGood(commit: String?) async throws {
        await simulateLatency()
    }

    public func bisectReset() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    public func bisectLog() async throws -> [String] {
        await simulateLatency()
        return [
            "# bad: [a1b2c3d] feat: add OAuth2 authentication flow",
            "# good: [86a1b2c] chore: initial project scaffold",
            "git bisect bad a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            "git bisect good 86a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"
        ]
    }

    // MARK: Interactive Rebase

    public func rebaseInteractive(onto base: String, steps: [RebaseStep]) async throws {
        await simulateLatency(150_000_000)
    }

    public func squashCommits(_ commits: [String], message: String) async throws {
        await simulateLatency(200_000_000)
    }

    public func rewordCommit(_ commit: String, newMessage: String) async throws {
        await simulateLatency(150_000_000)
    }

    public func dropCommit(_ commit: String) async throws {
        await simulateLatency(150_000_000)
    }

    // MARK: Reset

    public func resetToCommit(_ commit: String, mode: ResetMode) async throws {
        await simulateLatency(100_000_000)
        currentBranch = MockData.branches.first(where: { $0.isHEAD })
    }

    // MARK: Clean

    public func cleanUntracked(directories: Bool, force: Bool) async throws {
        await simulateLatency()
    }

    // MARK: Stash

    public func stashes() async throws -> [StashEntry] {
        await simulateLatency()
        return MockData.stashEntries
    }

    public func stashCreate(message: String?, includeUntracked: Bool, paths: [String]? = nil) async throws {
        await simulateLatency()
    }

    public func stashApply(index: Int, drop: Bool) async throws {
        await simulateLatency()
    }

    public func stashDrop(index: Int) async throws {
        await simulateLatency()
    }

    // MARK: Tags

    public func tags() async throws -> [TagInfo] {
        await simulateLatency()
        return MockData.tags
    }

    @discardableResult
    public func createTag(name: String, at sha: String?, message: String?, sign: Bool = false) async throws -> TagInfo {
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

    public func deleteTag(name: String) async throws {
        await simulateLatency()
    }

    public func pushTag(name: String, remote: String?) async throws {
        await simulateLatency(150_000_000)
    }

    public func pushAllTags(remote: String?) async throws {
        await simulateLatency(200_000_000)
    }

    // MARK: Submodules

    public func updateSubmodule(path: String) async throws {
        await simulateLatency()
    }

    public func updateSubmodule(path: String, toRemote: Bool) async throws {
        await simulateLatency()
    }

    public func initSubmodule(path: String) async throws {
        await simulateLatency()
    }

    public func fetchSubmodule(path: String) async throws {
        await simulateLatency()
    }

    public func submodules() async throws -> [SubmoduleInfo] {
        [
            SubmoduleInfo(name: "vendor/analytics", path: "vendor/analytics", url: "https://github.com/example/analytics.git",
                          sha: "1a2b3c4d5e6f7a8b9c0d", state: .upToDate),
            SubmoduleInfo(name: "vendor/icons", path: "vendor/icons", url: "https://github.com/example/icons.git",
                          sha: "9f8e7d6c5b4a39281706", state: .uninitialized)
        ]
    }

    // MARK: Worktrees

    public func worktrees() async throws -> [WorktreeInfo] {
        [
            WorktreeInfo(path: path.path, branch: "main", headSHA: "a1b2c3d4e5f6", isMain: true, isPrunable: false, isLocked: false),
            WorktreeInfo(path: path.path + "-feature-auth", branch: "feature/auth", headSHA: "b2c3d4e5f6a1",
                         isMain: false, isPrunable: false, isLocked: false)
        ]
    }

    public func removeWorktree(path: String, force: Bool) async throws {
        await simulateLatency()
    }

    // MARK: Working Copy

    public func commitIdentity() async -> CommitIdentity? {
        CommitIdentity(name: "Jane Developer", email: "jane@example.com")
    }

    public func operationContext() async -> OperationContext? {
        repositoryState == .normal ? nil : OperationContext(oursLabel: currentBranch?.name ?? "main", theirsLabel: "feature/auth")
    }

    public func continueOperation() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    public func conflictVersions(path: String) async throws -> ConflictVersions {
        ConflictVersions(ours: "let value = 1\n", theirs: "let value = 2\n")
    }
}
