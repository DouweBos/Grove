// BranchCIStatusTests.swift
// GroveTests
//
// CI status on branch rows: the newest commit's runs decide it, and it only shows while the branch is still on that commit.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct BranchCIStatusTests {

    private nonisolated func run(_ id: Int, _ branch: String?, sha: String, workflow: Int = 1, _ status: CIRunStatus) -> CIRun {
        let date = Date(timeIntervalSince1970: 1_790_000_000 + Double(id))
        return CIRun(id: id, number: id, attempt: 1, title: "Run \(id)", workflowID: workflow, workflowName: "W\(workflow)", event: "push",
                     branch: branch, headSHA: sha, status: status, actor: "jane", createdDate: date, updatedDate: date, startedDate: date,
                     webURL: "https://example.com/\(id)")
    }

    // MARK: Index

    @Test func githubReadsTheHundredNewestRunsOnce() async throws {
        let http = FakeHTTPClient { _ in (200, CIHostTests.runsResponse) }
        let index = try await CIHostTests.github(http).branchStatuses()
        #expect(index["feature/login"]?.status == .inProgress && index.count == 1, "Runs without a branch are skipped")
        #expect(http.requests.map { $0.url?.query ?? "" } == ["per_page=100"])
    }

    // MARK: Refs

    // MARK: Actions tab

    @Test func aRunFinishingInTheActionsTabUpdatesBranchRows() async throws {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        await session.refs.refresh()
        try await waitUntil { repo.ci.branchStatusRequests == 1 }
        await session.ciVM.refresh()
        let running = MockData.ciRuns[0]

        repo.ci.runs[0] = running.with(status: .failure, attempt: running.attempt)
        await session.ciVM.poll()

        try await waitUntil { repo.ci.branchStatusRequests == 2 }
        #expect(session.refs.branchCIStatuses[running.branch ?? ""]?.status == .failure)
    }

    @Test func showRunsForBranchOpensTheActionsTabFiltered() async throws {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        let remote = BranchInfo(id: "refs/remotes/origin/feature/auth", name: "origin/feature/auth", isLocal: false, isRemote: true,
                                isHEAD: false, targetSHA: "x", remoteName: "origin", upstream: nil, ahead: 0, behind: 0)

        session.sidebarVM.showRuns(for: remote)

        #expect(session.sidebarVM.selection == .ci)
        try await waitUntil { session.ciVM.hasLoaded && !session.ciVM.isLoading }
        #expect(session.ciVM.query == CIRunQuery(branch: "feature/auth"))
        #expect(session.ciVM.runs.map(\.branch) == ["feature/auth"])
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(25)) }
        #expect(condition())
    }
}
