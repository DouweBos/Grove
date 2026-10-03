// GitUndoManagerTests.swift
// GroveKitTests

import Foundation
import Testing
@testable import GroveKit

@MainActor
struct GitUndoManagerTests {

    private final class Log { var entries: [String] = [] }

    private struct Failure: Error {}

    private func action(_ name: String, log: Log, failUndo: Bool = false) -> GitUndoManager.GitAction {
        GitUndoManager.GitAction(
            description: name,
            undoCommand: {
                if failUndo { throw Failure() }
                log.entries.append("undo \(name)")
            },
            redoCommand: { log.entries.append("redo \(name)") }
        )
    }

    @Test func undoMovesActionToRedoStack() async throws {
        let manager = GitUndoManager()
        let log = Log()
        manager.record(action("Commit", log: log))
        #expect(manager.undoDescription == "Commit")

        try await manager.undo()
        #expect(!manager.canUndo)
        #expect(manager.redoDescription == "Commit")

        try await manager.redo()
        #expect(manager.undoDescription == "Commit")
        #expect(log.entries == ["undo Commit", "redo Commit"])
    }

    @Test func failedUndoStaysOnUndoStack() async {
        let manager = GitUndoManager()
        manager.record(action("Checkout", log: Log(), failUndo: true))

        await #expect(throws: Failure.self) { try await manager.undo() }
        #expect(manager.undoDescription == "Checkout")
        #expect(!manager.canRedo)
    }

    @Test func groupedActionUndoesInReverseOrder() async throws {
        let log = Log()
        let group = GitUndoManager.groupedAction(
            description: "Delete 2 Branches",
            actions: [action("a", log: log), action("b", log: log)]
        )
        try await group.undoCommand()
        try await group.redoCommand()
        #expect(log.entries == ["undo b", "undo a", "redo a", "redo b"])
    }

    @Test func recordingClearsRedoStack() async throws {
        let manager = GitUndoManager()
        let log = Log()
        manager.record(action("Stage", log: log))
        try await manager.undo()
        manager.record(action("Unstage", log: log))
        #expect(!manager.canRedo)
    }
}
