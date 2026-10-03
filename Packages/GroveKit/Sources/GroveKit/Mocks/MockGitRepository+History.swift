// Mocks/MockGitRepository+History.swift
// GroveKit

import Foundation

extension MockGitRepository {

    // MARK: Blame

    public func blame(file: String, revision: String?) async throws -> [BlameEntry] {
        await simulateLatency(120_000_000)
        return MockData.blameEntries
    }

    // MARK: Reflog

    public func reflog(maxCount: Int) async throws -> [ReflogEntry] {
        await simulateLatency()
        return Array(MockData.reflogEntries.prefix(maxCount))
    }

    // MARK: Pull Requests

    public func branchPullRequests() async throws -> [BranchPullRequest] {
        [BranchPullRequest(number: 42, title: "Add sign in", headBranch: "feature/auth", isDraft: false,
                           url: "https://github.com/example/app/pull/42", baseBranch: "main"),
         BranchPullRequest(number: 38, title: "Overhaul the UI", headBranch: "feature/ui-overhaul", isDraft: false,
                           url: "https://github.com/example/app/pull/38", baseBranch: "main",
                           isMerged: true, headSHA: MockData.commits[5].id)]
    }

    public func pullRequests() async throws -> [PullRequestInfo] {
        await simulateLatency(80_000_000)
        return MockData.pullRequests
    }

    public func pullRequestDetail(number: Int) async throws -> PullRequestInfo {
        await simulateLatency()
        return MockData.pullRequests.first(where: { $0.id == number }) ?? MockData.pullRequests[0]
    }

    public func pullRequestComments(number: Int) async throws -> [PRComment] {
        await simulateLatency(60_000_000)
        return MockData.prComments
    }

    public func checkoutPullRequest(number: Int) async throws {
        await simulateLatency(150_000_000)
        if let pr = MockData.pullRequests.first(where: { $0.id == number }) {
            currentBranch = BranchInfo(
                id: "refs/heads/\(pr.sourceBranch)",
                name: pr.sourceBranch,
                isLocal: true,
                isRemote: false,
                isHEAD: true,
                targetSHA: MockData.commits[0].id,
                remoteName: nil,
                upstream: nil,
                ahead: 0,
                behind: 0
            )
        }
    }

    public func closePullRequest(number: Int) async throws {
        await simulateLatency(80_000_000)
    }

    public func mergePullRequest(number: Int) async throws {
        await simulateLatency(200_000_000)
        currentBranch = MockData.branches.first(where: { $0.isHEAD })
    }

    public func createPullRequest(_ draft: PullRequestDraft) async throws -> String {
        await simulateLatency(200_000_000)
        return "https://github.com/example/app/pull/99"
    }

    public func defaultBranch(of remote: String) async -> String? { "main" }

    public func commentOnPullRequest(number: Int, body: String) async throws {
        await simulateLatency(120_000_000)
    }

    public func pullRequestReviewComments(number: Int) async throws -> [PRReviewComment] {
        await simulateLatency(60_000_000)
        return MockData.prReviewComments
    }
}
