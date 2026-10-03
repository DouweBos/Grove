// StackActionTests.swift
// GroveTests
//
// Pushing, moving and folding stack layers against scratch repositories and a bare remote under /tmp.

import Foundation
@testable import GroveKit
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
