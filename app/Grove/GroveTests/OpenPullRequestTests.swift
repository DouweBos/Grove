// OpenPullRequestTests.swift
// GroveTests

import Foundation
import Testing
@testable import Grove

@MainActor
struct OpenPullRequestTests {

    @Test func indexKeysByHeadBranchAndKeepsTheNewest() throws {
        let json = """
        [{"number":6549,"title":"Speed up Android CI","headRefName":"douwe/android-ci-build-speed","isDraft":false,"url":"https://github.com/o/r/pull/6549"},
         {"number":6100,"title":"Old attempt","headRefName":"douwe/android-ci-build-speed","isDraft":true,"url":"https://github.com/o/r/pull/6100"},
         {"number":6557,"title":"CLI params","headRefName":"douwe/device-login-cli-params","isDraft":true,"url":"https://github.com/o/r/pull/6557"}]
        """
        let index = try OpenPullRequest.index(fromJSON: Data(json.utf8))
        #expect(index["douwe/android-ci-build-speed"]?.number == 6549)
        #expect(index["douwe/device-login-cli-params"]?.label == "#6557")
        #expect(index["douwe/device-login-cli-params"]?.tooltip == "Draft pull request #6557: CLI params")
        #expect(index.count == 2)
    }

    @Test func refsMatchLocalAndRemoteBranches() async throws {
        let refs = RepositoryRefs(repository: MockGitRepository())
        refs.refreshPullRequests(force: true)
        for _ in 0..<50 where refs.openPullRequests.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }

        let local = BranchInfo(id: "refs/heads/feature/auth", name: "feature/auth", isLocal: true, isRemote: false,
                               isHEAD: false, targetSHA: "a", remoteName: nil, upstream: nil, ahead: 0, behind: 0)
        let remote = BranchInfo(id: "refs/remotes/origin/feature/auth", name: "origin/feature/auth", isLocal: false, isRemote: true,
                                isHEAD: false, targetSHA: "a", remoteName: "origin", upstream: nil, ahead: 0, behind: 0)
        #expect(refs.openPullRequest(for: local)?.number == 42)
        #expect(refs.openPullRequest(for: remote)?.number == 42)
    }
}
