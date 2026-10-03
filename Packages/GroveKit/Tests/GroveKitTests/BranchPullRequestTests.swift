// BranchPullRequestTests.swift
// GroveKitTests

import Foundation
import Testing
@testable import GroveKit

@MainActor
struct BranchPullRequestTests {

    private func pr(_ number: Int, _ head: String, merged: Bool = false, sha: String? = nil) -> BranchPullRequest {
        BranchPullRequest(number: number, title: "PR \(number)", headBranch: head, isDraft: false, url: "", isMerged: merged, headSHA: sha)
    }

    @Test func indexPrefersOpenThenTheNewestMerged() {
        let index = BranchPullRequest.index([
            pr(6100, "a"), pr(6549, "a"), pr(6600, "a", merged: true),
            pr(10, "b", merged: true), pr(12, "b", merged: true),
        ])
        #expect(index["a"]?.number == 6549)
        #expect(index["b"]?.number == 12)
        #expect(index["a"]?.tooltip == "Pull request #6549: PR 6549")
        #expect(index["b"]?.tooltip == "Merged pull request #12: PR 12")
    }

    @Test func mergedOnlyAppliesToABranchStillAtItsHead() {
        #expect(pr(1, "a").applies(toTip: "anything"))
        #expect(pr(1, "a", merged: true, sha: "abc123").applies(toTip: "abc123def"), "Bitbucket reports abbreviated hashes")
        #expect(!pr(1, "a", merged: true, sha: "abc123").applies(toTip: "fff000"))
        #expect(!pr(1, "a", merged: true).applies(toTip: "abc123"))
    }

    @Test func refsMatchLocalAndRemoteBranches() async throws {
        let refs = RepositoryRefs(repository: MockGitRepository())
        refs.refreshPullRequests(force: true)
        for _ in 0..<50 where refs.branchPullRequests.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }

        let local = BranchInfo(id: "refs/heads/feature/auth", name: "feature/auth", isLocal: true, isRemote: false,
                               isHEAD: false, targetSHA: "a", remoteName: nil, upstream: nil, ahead: 0, behind: 0)
        let remote = BranchInfo(id: "refs/remotes/origin/feature/auth", name: "origin/feature/auth", isLocal: false, isRemote: true,
                                isHEAD: false, targetSHA: "a", remoteName: "origin", upstream: nil, ahead: 0, behind: 0)
        #expect(refs.pullRequest(for: local)?.number == 42)
        #expect(refs.pullRequest(for: remote)?.number == 42)
    }

    @Test func refsHideAMergedPullRequestOnceTheBranchMovesOn() async throws {
        let refs = RepositoryRefs(repository: MockGitRepository())
        refs.refreshPullRequests(force: true)
        for _ in 0..<50 where refs.branchPullRequests.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }

        let merged = MockData.branches.first { $0.name == "feature/ui-overhaul" }!
        let moved = BranchInfo(id: merged.id, name: merged.name, isLocal: true, isRemote: false, isHEAD: false, targetSHA: "new",
                               remoteName: nil, upstream: nil, ahead: 0, behind: 0)
        #expect(refs.pullRequest(for: merged)?.isMerged == true)
        #expect(refs.pullRequest(for: moved) == nil)
    }
}
