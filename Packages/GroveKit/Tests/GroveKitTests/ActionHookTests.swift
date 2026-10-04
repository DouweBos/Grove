// ActionHookTests.swift
// GroveKitTests
//
// View models report the actions they run, and whether they worked, to the app's hook.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct ActionHookTests {

    private final class Log {
        var actions: [(GroveKitAction, Bool)] = []
    }

    @Test func workingCopyReportsStagingAndCommits() async throws {
        let log = Log()
        let viewModel = WorkingCopyViewModel(repository: MockGitRepository())
        viewModel.onAction = { log.actions.append(($0, $1)) }
        await viewModel.refresh()
        let entry = try #require(viewModel.unstagedFiles.first)

        await viewModel.stageFile(entry)
        viewModel.commitSubject = "Subject"
        await viewModel.commit()

        #expect(log.actions.map(\.0) == [.stage, .commit])
        #expect(log.actions.allSatisfy { $0.1 })
    }

    @Test func refActionsReportFailures() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grovekit-hook-\(UUID().uuidString)")
        let shell = GitShell(workingDirectory: FileManager.default.temporaryDirectory, runner: LocalGitRunner())
        try await shell.run(["init", "-q", "-b", "main", root.path])
        let repository = try await GitRepository(path: root, runner: LocalGitRunner())
        let actions = RefActionsViewModel(repository: repository, refs: RepositoryRefs(repository: repository, readsStatus: false))
        let log = Log()
        actions.onAction = { log.actions.append(($0, $1)) }

        let missing = BranchInfo(id: "nope", name: "nope", isLocal: true, isRemote: false, isHEAD: false,
                                 targetSHA: "", ahead: 0, behind: 0)
        await actions.checkout(branch: missing)
        #expect(log.actions.count == 1)
        #expect(log.actions.first?.0 == .checkout)
        #expect(log.actions.first?.1 == false)
    }

    @Test func actionNamesCarryNoUserData() {
        #expect(GroveKitAction.allCases.allSatisfy { $0.rawValue.allSatisfy { $0.isLowercase || $0 == "_" } })
    }
}
