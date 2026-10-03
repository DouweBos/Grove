// BranchCIStatusTests.swift
// GroveKitTests
//
// CI status on branch rows: the newest commit's runs decide it, and it only shows while the branch is still on that commit.

import Foundation
import Testing
@testable import GroveKit

@MainActor
struct BranchCIStatusTests {

    private nonisolated func run(_ id: Int, _ branch: String?, sha: String, workflow: Int = 1, _ status: CIRunStatus) -> CIRun {
        let date = Date(timeIntervalSince1970: 1_790_000_000 + Double(id))
        return CIRun(id: id, number: id, attempt: 1, title: "Run \(id)", workflowID: workflow, workflowName: "W\(workflow)", event: "push",
                     branch: branch, headSHA: sha, status: status, actor: "jane", createdDate: date, updatedDate: date, startedDate: date,
                     webURL: "https://example.com/\(id)")
    }

    // MARK: Index

    @Test func theWorstRunOfTheNewestCommitDecides() {
        let index = BranchCIStatus.index([
            run(9, "main", sha: "new", workflow: 1, .success), run(8, "main", sha: "new", workflow: 2, .failure),
            run(7, "main", sha: "new", workflow: 3, .inProgress), run(6, "main", sha: "old", workflow: 1, .failure),
            run(5, "feature", sha: "f1", .queued), run(4, nil, sha: "x", .failure)
        ])
        #expect(index["main"]?.status == .failure && index["main"]?.headSHA == "new" && index["main"]?.url == "https://example.com/8")
        #expect(index["main"]?.workflows == ["W2", "W3", "W1"], "The deciding workflow is named first")
        #expect(index["feature"]?.status == .queued && index.count == 2)
    }

    @Test func aPassingReRunClearsTheEarlierFailure() {
        let index = BranchCIStatus.index([run(9, "main", sha: "a", .success), run(8, "main", sha: "a", .failure)])
        #expect(index["main"]?.status == .success)
    }

    // MARK: Refs

    @Test func aStatusOnlyShowsWhileTheBranchIsOnThatCommit() async throws {
        let repo = MockGitRepository()
        let refs = RepositoryRefs(repository: repo)
        await refs.refresh()
        try await waitUntil { !refs.branchCIStatuses.isEmpty }
        let failing = try #require(refs.localBranches.first { $0.name == "feature/ui-overhaul" })
        #expect(refs.ciStatus(for: failing)?.status == .failure)
        #expect(refs.ciStatus(for: try #require(refs.headBranch))?.status == .success && !refs.isHeadFailingCI)

        let moved = BranchInfo(id: failing.id, name: failing.name, isLocal: true, isRemote: false, isHEAD: false,
                               targetSHA: MockData.commits[1].id, remoteName: nil, upstream: nil, ahead: 0, behind: 0)
        #expect(refs.ciStatus(for: moved) == nil, "The branch moved on; CI hasn't seen this commit")

        let remote = BranchInfo(id: "refs/remotes/origin/feature/ui-overhaul", name: "origin/feature/ui-overhaul", isLocal: false,
                                isRemote: true, isHEAD: false, targetSHA: failing.targetSHA, remoteName: "origin", upstream: nil,
                                ahead: 0, behind: 0)
        #expect(refs.ciStatus(for: remote)?.status == .failure, "Remote branches match by their name on the remote")
    }

    @Test func statusesAreReadAtMostOnceAMinuteUnlessForced() async throws {
        let repo = MockGitRepository()
        let refs = RepositoryRefs(repository: repo)
        await refs.refresh()
        try await waitUntil { repo.ci.branchStatusRequests == 1 && !refs.branchCIStatuses.isEmpty }

        await refs.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(repo.ci.branchStatusRequests == 1)

        refs.refreshCIStatuses(force: true)
        try await waitUntil { repo.ci.branchStatusRequests == 2 }
    }

    @Test func anUnsupportedHostLeavesBranchesUnmarked() async {
        let repo = MockGitRepository()
        repo.ci.error = .ciUnsupported(.gitlab)
        let refs = RepositoryRefs(repository: repo)
        await refs.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(refs.branchCIStatuses.isEmpty && refs.errorMessage == nil)
    }

    @Test func theCheckedOutBranchFailingIsFlagged() async throws {
        let repo = MockGitRepository()
        repo.ci.runs = [run(1, "main", sha: MockData.branches[0].targetSHA, .failure)]
        let refs = RepositoryRefs(repository: repo)
        await refs.refresh()
        try await waitUntil { !refs.branchCIStatuses.isEmpty }
        #expect(refs.isHeadFailingCI)
    }

    // MARK: Actions tab

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(25)) }
        #expect(condition())
    }
}
