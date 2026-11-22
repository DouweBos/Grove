// ViewModelCommandsTests.swift
// GroveKitTests
//
// The refs, reflog, review and stash view models, and their undo, only mutate through their commands.

import Foundation
@testable import GroveKit
import Testing

@MainActor
private final class SpyCommands: GitCommandPerforming {
    let features = GitFeatures.all
    private(set) var performed: [GitCommand] = []

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        performed.append(command)
    }
}

@MainActor
struct ViewModelCommandsTests {

    private let spy = SpyCommands()
    private let repository = MockGitRepository()

    private func refActions() -> RefActionsViewModel {
        let model = RefActionsViewModel(repository: repository, refs: RepositoryRefs(repository: repository))
        model.commands = spy
        return model
    }

    @Test func refActionsPerformTheirCommands() async throws {
        let model = refActions()
        let branch = BranchInfo(id: "refs/heads/topic", name: "topic", isLocal: true, isRemote: false, isHEAD: false,
                                targetSHA: "abc", ahead: 0, behind: 0)
        await model.checkout(branch: branch)
        try await model.renameBranch(branch, to: "renamed")
        await model.deleteBranch(branch, force: true)
        await model.merge(branch: branch)
        await model.rebase(onto: branch)
        await model.stashApply(index: 2)
        try await model.track(branch, remoteBranch: "origin/topic")
        await model.stopTracking(branch)
        #expect(spy.performed == [
            .checkout("topic"), .renameBranch(from: "topic", to: "renamed"), .deleteBranch(name: "topic", force: true),
            .merge("topic", squash: false), .rebase(onto: "topic"), .applyStash(index: 2, drop: false),
            .setUpstream(branch: "topic", upstream: "origin/topic"), .setUpstream(branch: "topic", upstream: nil),
        ])
    }

    @Test func undoGoesThroughTheSameCommands() async throws {
        let deletion = GitUndoManager.deleteBranchAction(branchName: "topic", sha: "abc", repository: repository, commands: spy)
        try await deletion.undoCommand()
        try await deletion.redoCommand()
        let checkout = GitUndoManager.checkoutAction(targetBranch: "topic", previousBranch: "main", repository: repository,
                                                     commands: spy)
        try await checkout.undoCommand()
        #expect(spy.performed == [
            .createBranch(name: "topic", from: "abc", checkout: false, track: false, parent: nil),
            .deleteBranch(name: "topic", force: true), .checkout("main"),
        ])
    }

    @Test func reflogCreatesItsBranchThroughThem() async {
        let model = ReflogViewModel(repository: repository)
        model.commands = spy
        await model.refresh()
        guard let entry = model.entries.first else {
            Issue.record("the mock repository has no reflog")
            return
        }
        model.beginCreateBranch(from: entry)
        await model.createBranch(named: "saved", checkout: true)
        #expect(spy.performed == [.createBranch(name: "saved", from: entry.newSHA, checkout: true, track: false, parent: nil)])
    }

    @Test func reviewDeletesThroughThem() async {
        let model = BranchesReviewViewModel(repository: repository)
        model.commands = spy
        await model.refresh()
        guard let branch = model.branches.first(where: \.isDeletable) else {
            Issue.record("the mock repository has no deletable branch")
            return
        }
        model.requestDelete([branch])
        guard let pending = model.pendingDelete else {
            Issue.record("nothing to confirm")
            return
        }
        await model.confirmDelete(pending)
        #expect(spy.performed == [.deleteBranch(name: branch.name, force: branch.category != .merged)])
    }
}
