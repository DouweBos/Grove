// DialogContextTests.swift
// GroveTests
//
// Grove's dialogs run through the commands they're given, refresh after, and offer pins and undo.

import Foundation
@testable import GroveKit
import GroveUIKit
import Testing
@testable import Grove

@MainActor
private final class SpyCommands: GitCommandPerforming {
    let features = GitFeatures.all
    private(set) var performed: [GitCommand] = []

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        performed.append(command)
    }
}

@MainActor
struct DialogContextTests {

    // Not through SidebarViewModel or BranchPins: both read Grove's real defaults.
    @Test func dialogsRunThroughTheGivenCommandsAndRefresh() async throws {
        let repository = MockGitRepository()
        let spy = SpyCommands()
        var refreshed = 0
        let undo = GitUndoManager()
        let context = GitDialogContext.grove(repository: repository, refs: RepositoryRefs(repository: repository),
                                             commands: spy, undo: undo) { refreshed += 1 }
        var create = GitCreateBranchForm(start: "main", localBranches: ["main"])
        create.name = "topic"
        create.checkout = false
        try await create.submit(in: context, progress: nil)
        await context.onChange?()
        #expect(spy.performed == [.createBranch(name: "topic", from: "main", checkout: false, track: false, parent: "main")])
        #expect(refreshed == 1 && undo.canUndo)
        #expect(context.pinBranch != nil)
        #expect(GitDialogContext.grove(repository: repository, refs: RepositoryRefs(repository: repository), undo: nil) {}
            .commands is RepositoryCommands)
    }
}
