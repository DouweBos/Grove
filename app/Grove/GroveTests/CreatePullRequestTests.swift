// CreatePullRequestTests.swift
// GroveTests

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct CreatePullRequestTests {

    private func commit(_ summary: String, body: String? = nil) -> CommitInfo {
        CommitInfo(id: UUID().uuidString, message: summary, summary: summary, body: body, authorName: "A", authorEmail: "a@x",
                   authorDate: Date(), committerName: "A", committerEmail: "a@x", committerDate: Date(), parentIDs: [], isSigned: false)
    }

    // MARK: Draft

    @Test func singleCommitSpeaksForItself() {
        let prefill = PullRequestDraft.prefill(head: "fix/crash", commits: [commit("Fix crash on launch", body: "Guard a nil window.\n")])
        #expect(prefill.title == "Fix crash on launch")
        #expect(prefill.body == "Guard a nil window.")
    }

    @Test func severalCommitsListOldestFirstUnderABranchTitle() {
        let prefill = PullRequestDraft.prefill(head: "douwe/add-login_screen",
                                               commits: [commit("Validate email"), commit("Add login view")])
        #expect(prefill.title == "Add login screen")
        #expect(prefill.body == "- Add login view\n- Validate email")
    }

    @Test func reviewersSplitOnCommasAndSpaces() {
        #expect(PullRequestDraft.reviewers(from: " @alice, bob  carol,,") == ["alice", "bob", "carol"])
        #expect(PullRequestDraft.reviewers(from: "").isEmpty)
    }

    @Test func defaultBasePrefersTheRemoteHead() {
        #expect(PullRequestDraft.defaultBase(remoteHead: "develop", candidates: ["main", "develop"]) == "develop")
        #expect(PullRequestDraft.defaultBase(remoteHead: nil, candidates: ["feature", "master"]) == "master")
        #expect(PullRequestDraft.defaultBase(remoteHead: nil, candidates: ["feature"]) == "feature")
    }

    @Test func numberComesFromTheURLTail() {
        #expect(PullRequestDraft.number(fromURL: "https://github.com/o/r/pull/123\n") == 123)
        #expect(PullRequestDraft.number(fromURL: "https://gitlab.com/o/r/-/merge_requests/7") == 7)
        #expect(PullRequestDraft.number(fromURL: "") == nil)
    }

    @Test func publishStateFollowsUpstreamAndAhead() {
        let branches = MockData.branches
        #expect(BranchPublishState(branch: branches.first { $0.name == "feature/ui-overhaul" }) == .unpublished)
        #expect(BranchPublishState(branch: branches.first { $0.name == "feature/auth" }) == .unpushed(3))
        #expect(BranchPublishState(branch: branches.first { $0.name == "develop" }) == .published)
    }

    @Test func githubBodyCarriesDraft() {
        let draft = PullRequestDraft(base: "main", head: "feat", title: "T", body: "B", isDraft: true, reviewers: ["a", "b"])
        let body = GitHubParser.createBody(draft)
        #expect(body["head"] as? String == "feat" && body["base"] as? String == "main" && body["draft"] as? Bool == true)
        #expect(body["reviewers"] == nil, "Reviewers go in their own request")
    }

    // MARK: View model

    private func makeViewModel(head: String?) -> CreatePullRequestViewModel {
        let repo = MockGitRepository()
        let refs = RepositoryRefs(repository: repo)
        refs.replace(localBranches: MockData.branches.filter(\.isLocal), remoteBranches: MockData.branches.filter(\.isRemote),
                     remotes: MockData.remotes)
        return CreatePullRequestViewModel(repository: repo, refs: refs, head: head)
    }

    @Test func loadPicksTheDefaultBaseAndPrefills() async {
        let viewModel = makeViewModel(head: "feature/ui-overhaul")
        await viewModel.load()
        #expect(viewModel.base == "main")
        #expect(viewModel.baseCandidates == ["develop", "main"])
        #expect(viewModel.title == "Ui overhaul")
        #expect(viewModel.canSubmit)
    }

    @Test func editedTitleSurvivesABranchChange() async {
        let viewModel = makeViewModel(head: "feature/ui-overhaul")
        await viewModel.load()
        viewModel.setTitle("My title")
        await viewModel.setBase("develop")
        #expect(viewModel.title == "My title")
    }

    @Test func unpublishedHeadAsksBeforePushing() async {
        let viewModel = makeViewModel(head: "feature/ui-overhaul")
        var created: String?
        viewModel.onCreated = { created = $0 }
        await viewModel.load()
        await viewModel.submit()
        #expect(viewModel.isConfirmingPush)
        #expect(created == nil)
        await viewModel.confirmPush()
        #expect(!viewModel.isConfirmingPush)
        #expect(created == "https://github.com/example/app/pull/99")
    }

    @Test func publishedHeadCreatesStraightAway() async {
        let viewModel = makeViewModel(head: "develop")
        var created: String?
        viewModel.onCreated = { created = $0 }
        await viewModel.load()
        #expect(viewModel.base == "main")
        await viewModel.submit()
        #expect(!viewModel.isConfirmingPush)
        #expect(created != nil)
    }

    @Test func headEqualToBaseCantSubmit() async {
        let viewModel = makeViewModel(head: "main")
        await viewModel.load()
        await viewModel.setBase("main")
        #expect(!viewModel.canSubmit)
    }
}
