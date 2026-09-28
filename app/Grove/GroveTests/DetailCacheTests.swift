// DetailCacheTests.swift
// GroveTests
//
// Detail panes cache per immutable identity: revisits skip git, misses start from a clean loading state.

import Foundation
import Testing
@testable import Grove

@MainActor
struct DetailCacheTests {

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test func historyRevisitIsInstant() async throws {
        let repo = MockGitRepository()
        let vm = HistoryViewModel(repository: repo)
        await vm.loadInitial()
        let first = try #require(vm.commits.first)
        let second = try #require(vm.commits.dropFirst().first)
        try await waitUntil { !vm.isLoadingDiff && vm.selectedSignature != nil }

        vm.select(second)
        #expect(vm.commitDiffs.isEmpty)
        #expect(vm.isLoadingDiff)
        try await waitUntil { !vm.isLoadingDiff }

        vm.select(first)
        #expect(!vm.commitDiffs.isEmpty)
        #expect(!vm.isLoadingDiff)
        #expect(vm.selectedSignature != nil)
        #expect(repo.callCounts["diffForCommit(_:)"] == 2)
    }

    @Test func historyTreeIsCachedPerCommit() async throws {
        let repo = MockGitRepository()
        let vm = HistoryViewModel(repository: repo)
        await vm.loadInitial()
        let first = try #require(vm.commits.first)
        let second = try #require(vm.commits.dropFirst().first)
        vm.selectDetailTab(.tree)
        try await waitUntil { !vm.treeFiles.isEmpty }
        vm.select(second)
        #expect(vm.treeFiles.isEmpty)
        try await waitUntil { !vm.treeFiles.isEmpty }
        vm.select(first)
        #expect(!vm.treeFiles.isEmpty)
        #expect(repo.callCounts["filesInCommit(_:)"] == 2)
    }

    @Test func stashRevisitSkipsGit() async throws {
        let repo = MockGitRepository()
        let vm = StashesViewModel(repository: repo)
        await vm.refresh()
        let stashes = vm.stashes
        await vm.select(stashes[0])
        await vm.select(stashes[1])
        await vm.select(stashes[0])
        #expect(!vm.stashDiffs.isEmpty)
        #expect(repo.callCounts["stashDiff(index:)"] == 2)
    }

    @Test func reflogRevisitSkipsGit() async throws {
        let repo = MockGitRepository()
        let vm = ReflogViewModel(repository: repo)
        await vm.refresh()
        let entries = vm.entries
        await vm.select(entries[0])
        await vm.select(entries[1])
        await vm.select(entries[0])
        #expect(vm.selectedCommit?.id == entries[0].newSHA)
        #expect(repo.callCounts["commitDetail(_:)"] == 2)
    }

    @Test func fileHistoryUsesPathLimitedDiffAndCaches() async throws {
        let repo = MockGitRepository()
        let path = try #require(MockData.commitFileDiffs.first { $0.status != .added }?.path)
        let vm = FileHistoryViewModel(repository: repo, filePath: path)
        await vm.loadHistory()
        let commits = vm.commits
        await vm.selectCommit(commits[1])
        await vm.selectCommit(commits[0])
        #expect(vm.fileDiff?.filePath == path)
        #expect(repo.callCounts["diffForCommit(_:path:)"] == 2)
        #expect(repo.callCounts["diffForCommit(_:)"] == nil)
    }

    @Test func blameRevisionIsCachedAndMissClears() async throws {
        let repo = MockGitRepository()
        let vm = BlameViewModel(repository: repo)
        await vm.open(file: "a.swift")
        let sha = try #require(vm.lines.compactMap(\.entry).first?.commitSHA)
        await vm.blameBefore(sha)
        await vm.goForward()
        await vm.blameBefore(sha)
        #expect(!vm.lines.isEmpty)
        // Working tree is re-read every time, the revision only once.
        #expect(repo.callCounts["blame(file:revision:)"] == 3)

        let task = Task { await vm.open(file: "b.swift") }
        try await waitUntil { vm.isLoadingBlame }
        #expect(vm.lines.isEmpty)
        await task.value
    }

    @Test func pullRequestRevisitShowsCacheWhileRevalidating() async throws {
        let repo = MockGitRepository()
        let vm = PullRequestsViewModel(repository: repo)
        await vm.refresh()
        let prs = vm.pullRequests
        await vm.select(prs[1])
        let task = Task { await vm.select(prs[0]) }
        try await waitUntil { vm.isRevalidating }
        #expect(!vm.comments.isEmpty)
        #expect(!vm.isLoadingComments)
        await task.value
        #expect(!vm.isRevalidating)
    }

    @Test func workingCopyDiffCacheAndCleanMiss() async throws {
        let repo = MockGitRepository()
        let vm = WorkingCopyViewModel(repository: repo)
        await vm.refresh()
        let files = vm.statusEntries.filter { !$0.isConflicted && !ImageDiffView.supports(path: $0.path) }
        await vm.select(files[0])
        let task = Task { await vm.select(files[1]) }
        try await waitUntil { vm.isDiffLoading }
        #expect(vm.currentDiff == nil)
        await task.value
        await vm.select(files[0])
        #expect(vm.currentDiff?.filePath == files[0].path)
        #expect(repo.callCounts["diff(for:staged:ignoreWhitespace:)"] == 2)
    }

    @Test func trackedFilesLoadOnlyForAllFilesMode() async throws {
        let repo = MockGitRepository()
        let vm = WorkingCopyViewModel(repository: repo)
        await vm.refresh()
        #expect(repo.callCounts["listTrackedFiles()"] == nil)
        await vm.setFileViewMode(.allFiles)
        #expect(!vm.allTrackedFiles.isEmpty)
        await vm.setFileViewMode(.flatModified)
        await vm.setFileViewMode(.allFiles)
        #expect(repo.callCounts["listTrackedFiles()"] == 1)
    }
}
