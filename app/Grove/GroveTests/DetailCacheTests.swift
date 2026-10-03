// DetailCacheTests.swift
// GroveTests
//
// Detail panes cache per immutable identity: revisits skip git, misses start from a clean loading state.

import Foundation
@testable import GroveKit
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

}
