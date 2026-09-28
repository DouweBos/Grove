// RestackTests.swift
// GroveTests
//
// Restacking against scratch repositories: a linear stack plus a split, a conflict mid-cascade, and a retarget.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct RestackTests {

    /// main → a → b → c, plus b → d; every layer touches its own file.
    private func buildStack() throws -> ScratchRepository {
        let repo = try ScratchRepository("restack")
        try repo.git(["checkout", "-q", "-b", "a"])
        try repo.commit("a.txt", "a\n", "a1")
        try repo.git(["checkout", "-q", "-b", "b"])
        try repo.commit("b.txt", "b\n", "b1")
        try repo.git(["checkout", "-q", "-b", "c"])
        try repo.commit("c.txt", "c\n", "c1")
        try repo.git(["checkout", "-q", "-b", "d", "b"])
        try repo.commit("d.txt", "d\n", "d1")
        try repo.git(["checkout", "-q", "main"])
        return repo
    }

    private func amend(_ repo: ScratchRepository, _ branch: String, _ file: String, _ text: String) throws {
        try repo.git(["checkout", "-q", branch])
        try Data(text.utf8).write(to: repo.root.appendingPathComponent(file))
        try repo.git(["commit", "-q", "-a", "--amend", "-m", "\(branch) amended"])
        try repo.git(["checkout", "-q", "main"])
    }

    private func loaded(_ repo: ScratchRepository) async throws -> (GitRepository, BranchStack) {
        let repository = try await GitRepository(path: repo.root)
        let refs = RepositoryRefs(repository: repository)
        await refs.refresh()
        return (repository, try #require(refs.stacks.first))
    }

    private func isAncestor(_ repo: ScratchRepository, _ ancestor: String, _ branch: String) -> Bool {
        (try? repo.git(["merge-base", "--is-ancestor", ancestor, branch])) != nil
    }

    @Test func restacksALinearStackAndASplitAfterTheRootIsAmended() async throws {
        let repo = try buildStack()
        try amend(repo, "a", "a.txt", "a amended\n")
        let (repository, stack) = try await loaded(repo)
        #expect(stack.layer("b")?.health.contains(.needsRestack) == true)

        let plan = RestackPlan.make(stack, mode: .drifted, trunkRef: "refs/heads/main", headBranch: "main")
        #expect(plan.steps.map(\.branch) == ["b", "c", "d"])
        try await repository.restack(plan)

        #expect(isAncestor(repo, "a", "b") && isAncestor(repo, "b", "c") && isAncestor(repo, "b", "d"))
        #expect(try repo.git(["rev-list", "--count", "a..b"]).trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect(try repo.git(["rev-list", "--count", "b..d"]).trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect(try repo.git(["branch", "--show-current"]).trimmingCharacters(in: .whitespacesAndNewlines) == "main")
        #expect(await repository.pendingRestack() == nil)

        let (_, after) = try await loaded(repo)
        #expect(after.layers.allSatisfy { !$0.health.contains(.needsRestack) })
    }

    @Test func conflictStopsTheCascadeThenAbortRestoresEveryLayer() async throws {
        let repo = try buildStack()
        try repo.git(["checkout", "-q", "b"])
        try repo.commit("a.txt", "b's take on a\n", "b2 edits a.txt")
        try repo.git(["checkout", "-q", "c"])
        try repo.git(["rebase", "-q", "b"])
        try repo.git(["checkout", "-q", "main"])
        try amend(repo, "a", "a.txt", "a rewritten\n")
        let before = try ["b", "c", "d"].map(repo.sha)
        let (repository, stack) = try await loaded(repo)

        let plan = RestackPlan.make(stack, mode: .drifted, trunkRef: "refs/heads/main", headBranch: "main")
        await #expect(throws: RestackError.self) { try await repository.restack(plan) }
        let pending = try #require(await repository.pendingRestack())
        #expect(pending.current?.branch == "b")
        #expect(pending.progressTitle == "Restacking 1 of 3: b")
        #expect(repository.repositoryState != .normal)

        try await repository.abortRestack()
        #expect(try ["b", "c", "d"].map(repo.sha) == before)
        #expect(await repository.pendingRestack() == nil)
        #expect(try repo.git(["branch", "--show-current"]).trimmingCharacters(in: .whitespacesAndNewlines) == "main")
    }

    @Test func conflictResolvedThenContinueFinishesTheCascade() async throws {
        let repo = try buildStack()
        try repo.git(["checkout", "-q", "b"])
        try repo.commit("a.txt", "b's take on a\n", "b2 edits a.txt")
        try repo.git(["checkout", "-q", "main"])
        try amend(repo, "a", "a.txt", "a rewritten\n")
        let (repository, stack) = try await loaded(repo)

        let plan = RestackPlan.make(stack, mode: .drifted, trunkRef: "refs/heads/main", headBranch: "main")
        await #expect(throws: RestackError.self) { try await repository.restack(plan) }
        try Data("resolved\n".utf8).write(to: repo.root.appendingPathComponent("a.txt"))
        try repo.git(["add", "a.txt"])
        try await repository.continueRestack()

        #expect(await repository.pendingRestack() == nil)
        #expect(isAncestor(repo, "a", "b") && isAncestor(repo, "b", "c") && isAncestor(repo, "b", "d"))
        #expect(try repo.git(["show", "c:a.txt"]) == "resolved\n")
    }

    @Test func retargetMovesChildrenOfAMergedParentOntoTrunk() async throws {
        let repo = try buildStack()
        try repo.git(["merge", "-q", "--squash", "a"])
        try repo.git(["commit", "-q", "-m", "Squash-merge a"])
        let (repository, stack) = try await loaded(repo)

        let plan = RestackPlan.make(stack, mode: .retarget(merged: "a"), trunkRef: "refs/heads/main", headBranch: "main")
        #expect(plan.steps.map(\.onto) == ["refs/heads/main", "b", "b"])
        try await repository.restack(plan)

        #expect(isAncestor(repo, "main", "b"))
        #expect(try repo.git(["rev-list", "--count", "main..b"]).trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect(isAncestor(repo, "b", "c") && isAncestor(repo, "b", "d"))
    }

    @Test func refusesToStartWithLocalChanges() async throws {
        let repo = try buildStack()
        try amend(repo, "a", "a.txt", "a amended\n")
        try Data("dirty\n".utf8).write(to: repo.root.appendingPathComponent("base.txt"))
        let (repository, stack) = try await loaded(repo)
        let plan = RestackPlan.make(stack, mode: .drifted, trunkRef: "refs/heads/main", headBranch: "main")
        await #expect(throws: RestackError.dirtyWorktree) { try await repository.restack(plan) }
    }

    @Test func layerInAnotherWorktreeIsRebasedThere() async throws {
        let repo = try buildStack()
        let worktree = repo.root.appendingPathExtension("d")
        try repo.git(["worktree", "add", "-q", worktree.path, "d"])
        try amend(repo, "a", "a.txt", "a amended\n")
        let (repository, stack) = try await loaded(repo)
        #expect(stack.layer("d")?.worktreePath != nil)

        try await repository.restack(RestackPlan.make(stack, mode: .drifted, trunkRef: "refs/heads/main", headBranch: "main"))
        #expect(isAncestor(repo, "b", "d"))
        #expect(try repo.git(["status", "--porcelain"], in: worktree).isEmpty)
    }
}

@MainActor
struct RestackPlanTests {

    @Test func driftedMovesTheDriftedLayerAndEverythingAbove() {
        let plan = RestackPlan.make(MockData.linearStack, mode: .drifted, trunkRef: "refs/heads/main", headBranch: nil)
        #expect(plan.steps.map(\.branch) == ["douwe/companion-20-music", "douwe/companion-21-ota", "douwe/companion-22-streams"])
        #expect(plan.steps.first?.onto == "douwe/companion-19-cast-connect")
    }

    @Test func ontoTrunkMovesEveryLayerRootFirst() {
        let plan = RestackPlan.make(MockData.splitStack, mode: .ontoTrunk, trunkRef: "refs/remotes/origin/main", headBranch: "auth-ui")
        #expect(plan.steps.map(\.branch) == ["auth-api", "auth-ui", "auth-ui-tests", "auth-docs"])
        #expect(plan.steps.map(\.onto) == ["refs/remotes/origin/main", "auth-api", "auth-ui", "auth-ui"])
        #expect(plan.originalBranch == "auth-ui")
    }

    @Test func fromAndMoveCoverTheSubtree() {
        let from = RestackPlan.make(MockData.splitStack, mode: .from("auth-ui"), trunkRef: "main", headBranch: nil)
        #expect(from.steps.map(\.branch) == ["auth-ui", "auth-ui-tests", "auth-docs"])
        let move = RestackPlan.make(MockData.splitStack, mode: .move("auth-docs", onto: "main"), trunkRef: "main", headBranch: nil)
        #expect(move.steps.map(\.branch) == ["auth-docs"])
        #expect(move.steps.first?.onto == "main")
    }
}
