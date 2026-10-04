// RefActionsTests.swift
// GroveKitTests
//
// Branch actions a refs list runs, with their undo records, against a scratch repository.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct RefActionsTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grovekit-refactions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "Tester"], ["config", "user.email", "t@example.com"],
                     ["config", "commit.gpgsign", "false"], ["commit", "-q", "--allow-empty", "-m", "first"],
                     ["branch", "feature"]] {
            try git(args)
        }
    }

    private func makeActions() async throws -> RefActionsViewModel {
        let repository = try await GitRepository(path: root, runner: LocalGitRunner())
        let refs = RepositoryRefs(repository: repository, readsStatus: false)
        await refs.refresh()
        let actions = RefActionsViewModel(repository: repository, refs: refs)
        actions.undoManager = GitUndoManager()
        return actions
    }

    @Test func checkoutIsUndoable() async throws {
        let actions = try await makeActions()
        let feature = try #require(actions.refs.localBranches.first { $0.name == "feature" })
        await actions.checkout(branch: feature)
        #expect(actions.refs.localBranches.first(where: \.isHEAD)?.name == "feature")
        #expect(actions.undoManager?.canUndo == true)
        try await actions.undoManager?.undo()
        await actions.refs.refresh()
        #expect(actions.refs.localBranches.first(where: \.isHEAD)?.name == "main")
    }

    @Test func renamesAndDeletesBranches() async throws {
        let actions = try await makeActions()
        let feature = try #require(actions.refs.localBranches.first { $0.name == "feature" })
        try await actions.renameBranch(feature, to: "topic")
        #expect(actions.refs.localBranches.map(\.name).sorted() == ["main", "topic"])

        let topic = try #require(actions.refs.localBranches.first { $0.name == "topic" })
        await actions.deleteBranch(topic)
        #expect(actions.refs.localBranches.map(\.name) == ["main"])
        #expect(actions.undoManager?.canUndo == true)
    }

    @Test func failureLandsInErrorMessage() async throws {
        let actions = try await makeActions()
        let main = try #require(actions.refs.localBranches.first { $0.name == "main" })
        await actions.deleteBranch(main)
        #expect(actions.errorMessage != nil)
        actions.dismissError()
        #expect(actions.errorMessage == nil)
    }

    private func git(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: "")
        }
    }
}
