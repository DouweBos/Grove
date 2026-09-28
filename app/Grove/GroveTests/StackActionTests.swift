// StackActionTests.swift
// GroveTests
//
// Pushing, moving and folding stack layers against scratch repositories and a bare remote under /tmp.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct StackActionTests {

    /// main → a → b → c, all pushed to a bare remote.
    private func pushedStack() throws -> (ScratchRepository, URL) {
        let repo = try ScratchRepository("stack-push")
        let remote = repo.root.appendingPathExtension("git")
        try repo.git(["init", "-q", "--bare", "-b", "main", remote.path])
        try repo.git(["remote", "add", "origin", remote.path])
        try repo.git(["push", "-q", "-u", "origin", "main"])
        for (branch, parent) in [("a", "main"), ("b", "a"), ("c", "b")] {
            try repo.git(["checkout", "-q", "-b", branch, parent])
            try repo.commit("\(branch).txt", "\(branch)\n", "\(branch)1")
        }
        try repo.git(["push", "-q", "-u", "origin", "a", "b", "c"])
        try repo.git(["checkout", "-q", "main"])
        return (repo, remote)
    }

    private func viewModel(_ repo: ScratchRepository) async throws -> StackViewModel {
        let repository = try await GitRepository(path: repo.root)
        let refs = RepositoryRefs(repository: repository)
        await refs.refresh()
        let vm = StackViewModel(repository: repository, refs: refs)
        vm.onRepositoryChanged = { await refs.refresh() }
        return vm
    }

    @Test func pushStackForcesOnlyChangedLayersWithALease() async throws {
        let (repo, remote) = try pushedStack()
        try repo.git(["checkout", "-q", "a"])
        try repo.git(["commit", "-q", "--amend", "-m", "a1 amended"])
        try repo.git(["checkout", "-q", "main"])
        let vm = try await viewModel(repo)
        await vm.restackDrifted()
        #expect(vm.errorMessage == nil)
        let stack = try #require(vm.stack)
        #expect(Set(vm.changedLayers(stack).map(\.branch)) == ["a", "b", "c"])

        await vm.pushStack()
        #expect(vm.errorMessage == nil)
        for branch in ["a", "b", "c"] {
            #expect(try repo.git(["rev-parse", branch]) == repo.git(["rev-parse", "refs/heads/\(branch)"], in: remote))
        }
    }

    @Test func pushStackChangesNothingWhenOneLeaseFails() async throws {
        let (repo, remote) = try pushedStack()
        // Someone else moves c on the remote.
        let other = repo.root.appendingPathExtension("other")
        try repo.git(["clone", "-q", "-b", "c", remote.path, other.path])
        try repo.commit("x.txt", "x\n", "theirs", in: other)
        try repo.git(["push", "-q", "origin", "c"], in: other)
        let remoteA = try repo.git(["rev-parse", "refs/heads/a"], in: remote)

        try repo.git(["checkout", "-q", "a"])
        try repo.git(["commit", "-q", "--amend", "-m", "a1 amended"])
        try repo.git(["checkout", "-q", "main"])
        let vm = try await viewModel(repo)
        await vm.restackDrifted()
        await vm.pushStack()
        #expect(vm.errorMessage != nil)
        #expect(try repo.git(["rev-parse", "refs/heads/a"], in: remote) == remoteA)
    }

    @Test func foldMovesTheParentOverTheLayerAndDropsIt() async throws {
        let (repo, _) = try pushedStack()
        let vm = try await viewModel(repo)
        let c = try #require(vm.stack?.layer("c"))
        #expect(vm.canFold(c))
        await vm.fold(c)
        #expect(vm.errorMessage == nil)
        #expect(try repo.sha("b") == repo.sha("origin/c"))
        #expect(throws: (any Error).self) { try repo.git(["rev-parse", "--verify", "refs/heads/c"]) }
    }

    @Test func moveRebasesALayerAndItsChildrenOntoAnotherBranch() async throws {
        let (repo, _) = try pushedStack()
        let vm = try await viewModel(repo)
        let b = try #require(vm.stack?.layer("b"))
        #expect(vm.moveTargets(for: b).contains("main"))
        await vm.move(b, onto: "main")
        #expect(vm.errorMessage == nil)
        #expect(try repo.git(["rev-list", "--count", "main..b"]).trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        #expect((try? repo.git(["merge-base", "--is-ancestor", "b", "c"])) != nil)
        #expect((try? repo.git(["merge-base", "--is-ancestor", "a", "b"])) == nil)
    }

    @Test func newPullRequestIsBasedOnTheRecognizedParent() async throws {
        let (repo, _) = try pushedStack()
        let repository = try await GitRepository(path: repo.root)
        let refs = RepositoryRefs(repository: repository)
        await refs.refresh()
        let creation = CreatePullRequestViewModel(repository: repository, refs: refs, head: "c")
        await creation.load()
        #expect(creation.base == "b")
    }
}
