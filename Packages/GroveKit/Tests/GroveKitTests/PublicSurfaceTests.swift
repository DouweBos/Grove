// PublicSurfaceTests.swift
// GroveKitTests
//
// State and defaults an app reads from outside GroveKit, through its public API only.

import Foundation
import GroveKit
import Testing

/// A code host that only knows a diff, as an app relaying another service would write it.
private nonisolated struct DiffOnlyHost: PullRequestHost {
    var kind: HostingServiceKind { .github }
    private var unsupported: HostingError { .noHostedRemote }
    func pullRequests() async throws -> [PullRequestInfo] { throw unsupported }
    func branchPullRequests() async throws -> [BranchPullRequest] { throw unsupported }
    func pullRequest(number: Int) async throws -> PullRequestInfo { throw unsupported }
    func comments(number: Int) async throws -> [PRComment] { throw unsupported }
    func reviewComments(number: Int) async throws -> [PRReviewComment] { throw unsupported }
    func commits(number: Int) async throws -> [CommitInfo] { throw unsupported }
    func diff(number: Int) async throws -> String? { nil }
    func merge(number: Int) async throws { throw unsupported }
    func close(number: Int) async throws { throw unsupported }
    func updateBase(number: Int, base: String) async throws { throw unsupported }
    func comment(number: Int, body: String) async throws { throw unsupported }
    func create(_ draft: PullRequestDraft) async throws -> String { throw unsupported }
    func webURL(number: Int) async throws -> URL? { nil }
}

struct PublicSurfaceTests {

    @Test nonisolated func pullRequestHostDefaultsAreNonisolated() {
        #expect(DiffOnlyHost().headRef(number: 1) == nil)
    }

    @Test func listSelectionExposesItsFocus() {
        var selection = ListSelection<String>()
        selection.select("a")
        #expect(selection.focus == "a")
    }

    @MainActor
    @Test func workingCopyStateIsReadable() async {
        let viewModel = WorkingCopyViewModel(repository: MockGitRepository())
        await viewModel.refresh()
        let path: String? = viewModel.selectedPath
        let action: KeyPath<PendingHunkDiscard, HunkAction> = \.action
        let steps: KeyPath<RestackPlan, [RestackPlan.Step]> = \.steps
        let branch: KeyPath<RestackPlan.Step, String> = \.branch
        _ = (path, action, steps, branch)
    }
}
