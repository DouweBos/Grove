// SidebarViewModelTests.swift
// GroveTests
//
// Tests for SidebarViewModel — verifies refresh resilience (one failing
// data source doesn't block others) and derived computed properties.

import Foundation
import Testing
@testable import Grove

// MARK: - FailingMockRepository

/// A wrapper that delegates to MockGitRepository but can inject failures.
@MainActor
@Observable
private final class FailingMockRepository: GitRepositoryProtocol {

    private let backing = MockGitRepository()

    var shouldFailStatus = false
    var shouldFailTags = false
    var shouldFailRemotes = false
    var shouldFailLocalBranches = false
    var shouldFailRemoteBranches = false

    var path: URL { backing.path }
    var displayName: String { backing.displayName }
    var currentBranch: BranchInfo? { backing.currentBranch }
    var repositoryState: RepositoryState { backing.repositoryState }

    private func failIf(_ shouldFail: Bool, _ name: String) throws {
        if shouldFail {
            throw FailError(name: name)
        }
    }

    struct FailError: LocalizedError {
        let name: String
        var errorDescription: String? { "Intentional failure in \(name)" }
    }

    // Overridable methods

    func status() async throws -> [StatusEntry] {
        try failIf(shouldFailStatus, "status")
        return try await backing.status()
    }

    func tags() async throws -> [TagInfo] {
        try failIf(shouldFailTags, "tags")
        return try await backing.tags()
    }

    func remotes() async throws -> [RemoteInfo] {
        try failIf(shouldFailRemotes, "remotes")
        return try await backing.remotes()
    }

    func localBranches() async throws -> [BranchInfo] {
        try failIf(shouldFailLocalBranches, "localBranches")
        return try await backing.localBranches()
    }

    func remoteBranches() async throws -> [BranchInfo] {
        try failIf(shouldFailRemoteBranches, "remoteBranches")
        return try await backing.remoteBranches()
    }

    // Pass-through for all other protocol requirements

    func refreshStatus() async throws { try await backing.refreshStatus() }
    func listTrackedFiles() async throws -> [String] { try await backing.listTrackedFiles() }
    func stage(paths: [String]) async throws { try await backing.stage(paths: paths) }
    func unstage(paths: [String]) async throws { try await backing.unstage(paths: paths) }
    func stageHunk(_ hunk: HunkData, in file: String) async throws { try await backing.stageHunk(hunk, in: file) }
    func unstageHunk(_ hunk: HunkData, in file: String) async throws { try await backing.unstageHunk(hunk, in: file) }
    func stageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws { try await backing.stageLines(lines, in: hunk, file: file) }
    func unstageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws { try await backing.unstageLines(lines, in: hunk, file: file) }
    func stageAll() async throws { try await backing.stageAll() }
    func unstageAll() async throws { try await backing.unstageAll() }
    func discardChanges(paths: [String]) async throws { try await backing.discardChanges(paths: paths) }
    func discardHunk(_ hunk: HunkData, in file: String) async throws { try await backing.discardHunk(hunk, in: file) }
    func discardLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws { try await backing.discardLines(lines, in: hunk, file: file) }
    func diff(for entry: StatusEntry, staged: Bool, ignoreWhitespace: Bool) async throws -> DiffResult { try await backing.diff(for: entry, staged: staged, ignoreWhitespace: ignoreWhitespace) }
    func diffForCommit(_ sha: String) async throws -> [FileDiff] { try await backing.diffForCommit(sha) }
    @discardableResult func commit(message: String, body: String?, amend: Bool, sign: Bool) async throws -> CommitInfo {
        try await backing.commit(message: message, body: body, amend: amend, sign: sign)
    }
    func isSigningConfigured() async throws -> Bool { try await backing.isSigningConfigured() }
    func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo] { try await backing.log(maxCount: maxCount, skip: skip, branch: branch) }
    func commitDetail(_ sha: String) async throws -> CommitInfo { try await backing.commitDetail(sha) }
    func fileLog(path: String, maxCount: Int) async throws -> [CommitInfo] { try await backing.fileLog(path: path, maxCount: maxCount) }
    @discardableResult func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo { try await backing.createBranch(name: name, from: from, checkout: checkout) }
    func checkout(branch: String) async throws { try await backing.checkout(branch: branch) }
    func deleteBranch(name: String, force: Bool) async throws { try await backing.deleteBranch(name: name, force: force) }
    func deleteRemoteBranch(name: String, remote: String) async throws { try await backing.deleteRemoteBranch(name: name, remote: remote) }
    func renameBranch(oldName: String, newName: String) async throws { try await backing.renameBranch(oldName: oldName, newName: newName) }
    func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws { try await backing.fetch(remote: remote, progress: progress) }
    func pull(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws { try await backing.pull(remote: remote, strategy: strategy, progress: progress) }
    func push(remote: String?, forceWithLease: Bool, setUpstream: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        try await backing.push(remote: remote, forceWithLease: forceWithLease, setUpstream: setUpstream, progress: progress)
    }
    func sync(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws { try await backing.sync(remote: remote, strategy: strategy, progress: progress) }
    func merge(branch: String) async throws { try await backing.merge(branch: branch) }
    func abortMerge() async throws { try await backing.abortMerge() }
    func rebase(onto: String) async throws { try await backing.rebase(onto: onto) }
    func abortRebase() async throws { try await backing.abortRebase() }
    func continueRebase() async throws { try await backing.continueRebase() }
    func conflicts() async throws -> [StatusEntry] { try await backing.conflicts() }
    func cherryPick(commit: String) async throws { try await backing.cherryPick(commit: commit) }
    func abortCherryPick() async throws { try await backing.abortCherryPick() }
    func revert(commit: String) async throws { try await backing.revert(commit: commit) }
    func abortRevert() async throws { try await backing.abortRevert() }
    func bisectStart() async throws { try await backing.bisectStart() }
    func bisectBad(commit: String?) async throws { try await backing.bisectBad(commit: commit) }
    func bisectGood(commit: String?) async throws { try await backing.bisectGood(commit: commit) }
    func bisectReset() async throws { try await backing.bisectReset() }
    func bisectLog() async throws -> [String] { try await backing.bisectLog() }
    func rebaseInteractive(onto base: String, steps: [RebaseStep]) async throws { try await backing.rebaseInteractive(onto: base, steps: steps) }
    func squashCommits(_ commits: [String], message: String) async throws { try await backing.squashCommits(commits, message: message) }
    func rewordCommit(_ commit: String, newMessage: String) async throws { try await backing.rewordCommit(commit, newMessage: newMessage) }
    func dropCommit(_ commit: String) async throws { try await backing.dropCommit(commit) }
    func resetToCommit(_ commit: String, mode: ResetMode) async throws { try await backing.resetToCommit(commit, mode: mode) }
    func cleanUntracked(directories: Bool, force: Bool) async throws { try await backing.cleanUntracked(directories: directories, force: force) }
    func stashes() async throws -> [StashEntry] { try await backing.stashes() }
    func stashCreate(message: String?, includeUntracked: Bool, paths: [String]?) async throws { try await backing.stashCreate(message: message, includeUntracked: includeUntracked, paths: paths) }
    func stashApply(index: Int, drop: Bool) async throws { try await backing.stashApply(index: index, drop: drop) }
    func stashDrop(index: Int) async throws { try await backing.stashDrop(index: index) }
    @discardableResult func createTag(name: String, at sha: String?, message: String?, sign: Bool) async throws -> TagInfo {
        try await backing.createTag(name: name, at: sha, message: message, sign: sign)
    }
    func deleteTag(name: String) async throws { try await backing.deleteTag(name: name) }
    func pushTag(name: String, remote: String?) async throws { try await backing.pushTag(name: name, remote: remote) }
    func pushAllTags(remote: String?) async throws { try await backing.pushAllTags(remote: remote) }
    func updateSubmodule(path: String) async throws { try await backing.updateSubmodule(path: path) }
    func removeWorktree(path: String, force: Bool) async throws { try await backing.removeWorktree(path: path, force: force) }
    func blame(file: String, revision: String?) async throws -> [BlameEntry] { try await backing.blame(file: file, revision: revision) }
    func reflog(maxCount: Int) async throws -> [ReflogEntry] { try await backing.reflog(maxCount: maxCount) }
    func pullRequests() async throws -> [PullRequestInfo] { try await backing.pullRequests() }
    func pullRequestDetail(number: Int) async throws -> PullRequestInfo { try await backing.pullRequestDetail(number: number) }
    func pullRequestComments(number: Int) async throws -> [PRComment] { try await backing.pullRequestComments(number: number) }
    func checkoutPullRequest(number: Int) async throws { try await backing.checkoutPullRequest(number: number) }
    func closePullRequest(number: Int) async throws { try await backing.closePullRequest(number: number) }
    func mergePullRequest(number: Int) async throws { try await backing.mergePullRequest(number: number) }
    func ignore(patterns: [String], localOnly: Bool) async throws { try await backing.ignore(patterns: patterns, localOnly: localOnly) }
    func stopTracking(paths: [String]) async throws { try await backing.stopTracking(paths: paths) }
    func moveFile(from source: String, to destination: String) async throws { try await backing.moveFile(from: source, to: destination) }
    func restoreFile(_ path: String, from revision: String, revisionPath: String) async throws {
        try await backing.restoreFile(path, from: revision, revisionPath: revisionPath)
    }
    func patch(paths: [String], staged: Bool) async throws -> String { try await backing.patch(paths: paths, staged: staged) }
    func commitTemplate() async -> String? { await backing.commitTemplate() }
    @discardableResult func saveSnapshot(message: String, includeUntracked: Bool) async throws -> Bool {
        try await backing.saveSnapshot(message: message, includeUntracked: includeUntracked)
    }
    func applyPatch(at file: URL, toIndex: Bool, checkOnly: Bool) async throws {
        try await backing.applyPatch(at: file, toIndex: toIndex, checkOnly: checkOnly)
    }
}

// MARK: - SidebarViewModelTests

@MainActor
struct SidebarViewModelTests {

    // MARK: Normal refresh

    @Test func refresh_populatesAllData() async {
        let repo = MockGitRepository()
        let vm = SidebarViewModel(repository: repo)

        await vm.refresh()

        #expect(!vm.localBranches.isEmpty)
        #expect(!vm.remoteBranches.isEmpty)
        #expect(!vm.tags.isEmpty)
        #expect(!vm.remotes.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    // MARK: Resilient refresh — one failure doesn't block others

    @Test func refresh_statusFailure_branchesStillLoad() async {
        let repo = FailingMockRepository()
        repo.shouldFailStatus = true
        let vm = SidebarViewModel(repository: repo)

        await vm.refresh()

        #expect(!vm.localBranches.isEmpty, "Branches should load even when status() fails")
        #expect(!vm.remoteBranches.isEmpty, "Remote branches should load even when status() fails")
        #expect(!vm.tags.isEmpty, "Tags should load even when status() fails")
        #expect(!vm.remotes.isEmpty, "Remotes should load even when status() fails")
        #expect(vm.errorMessage != nil, "Error message should be set")
    }

    @Test func refresh_tagsFailure_branchesStillLoad() async {
        let repo = FailingMockRepository()
        repo.shouldFailTags = true
        let vm = SidebarViewModel(repository: repo)

        await vm.refresh()

        #expect(!vm.localBranches.isEmpty, "Branches should load even when tags() fails")
        #expect(!vm.remoteBranches.isEmpty)
        #expect(!vm.remotes.isEmpty)
        #expect(vm.tags.isEmpty, "Tags should remain empty when tags() fails")
        #expect(vm.errorMessage != nil)
    }

    @Test func refresh_remotesFailure_branchesAndTagsStillLoad() async {
        let repo = FailingMockRepository()
        repo.shouldFailRemotes = true
        let vm = SidebarViewModel(repository: repo)

        await vm.refresh()

        #expect(!vm.localBranches.isEmpty)
        #expect(!vm.tags.isEmpty)
        #expect(vm.remotes.isEmpty, "Remotes should remain empty when remotes() fails")
        #expect(vm.errorMessage != nil)
    }

    @Test func refresh_localBranchesFailure_remotesAndTagsStillLoad() async {
        let repo = FailingMockRepository()
        repo.shouldFailLocalBranches = true
        let vm = SidebarViewModel(repository: repo)

        await vm.refresh()

        #expect(vm.localBranches.isEmpty)
        #expect(!vm.remoteBranches.isEmpty, "Remote branches should load even when localBranches() fails")
        #expect(!vm.tags.isEmpty, "Tags should load even when localBranches() fails")
        #expect(!vm.remotes.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    // MARK: localBranchGroups — shows all branches

    @Test func localBranchGroups_includesAllLocalBranches() async {
        let repo = MockGitRepository()
        let vm = SidebarViewModel(repository: repo)

        await vm.refresh()

        let allGroupedBranches = vm.localBranchGroups.flatMap(\.branches)
        #expect(allGroupedBranches.count == vm.localBranches.count,
                "localBranchGroups should contain all local branches, not just active ones")
    }
}
