// Mocks/MockGitRepository+History.swift
// Grove

import Foundation

extension MockGitRepository {

    // MARK: Blame

    func blame(file: String, revision: String?) async throws -> [BlameEntry] {
        await simulateLatency(120_000_000)
        return MockData.blameEntries
    }

    // MARK: Reflog

    func reflog(maxCount: Int) async throws -> [ReflogEntry] {
        await simulateLatency()
        return Array(MockData.reflogEntries.prefix(maxCount))
    }

    // MARK: Pull Requests

    func pullRequests() async throws -> [PullRequestInfo] {
        await simulateLatency(80_000_000)
        return MockData.pullRequests
    }

    func pullRequestDetail(number: Int) async throws -> PullRequestInfo {
        await simulateLatency()
        return MockData.pullRequests.first(where: { $0.id == number }) ?? MockData.pullRequests[0]
    }

    func pullRequestComments(number: Int) async throws -> [PRComment] {
        await simulateLatency(60_000_000)
        return MockData.prComments
    }

    func checkoutPullRequest(number: Int) async throws {
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

    func closePullRequest(number: Int) async throws {
        await simulateLatency(80_000_000)
    }

    func mergePullRequest(number: Int) async throws {
        await simulateLatency(200_000_000)
        currentBranch = MockData.branches.first(where: { $0.isHEAD })
    }
}
