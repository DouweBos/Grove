// HistoryRewriteTests.swift
// GroveTests
//
// Squashing a selection and interactive rebase plans, against a scratch repository.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct HistoryRewriteTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-rewrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        for index in 1...5 {
            try write("f\(index).txt", "\(index)\n")
            try commitAll("commit \(index)")
        }
    }

    private func loadedHistory() async throws -> HistoryViewModel {
        let vm = HistoryViewModel(repository: try await GitRepository(path: root))
        vm.undoManager = GitUndoManager()
        await vm.loadInitial()
        return vm
    }

    @Test func squashesASelectedRunIntoOneUndoableCommit() async throws {
        let vm = try await loadedHistory()
        let oldHead = vm.commits[0].id
        let run = Array(vm.commits[1...3])
        #expect(vm.canSquash(run))
        await vm.squash(run, message: vm.squashMessage(for: run))
        #expect(vm.errorMessage == nil)

        let subjects = try git(["log", "--format=%s"]).split(separator: "\n")
        #expect(subjects == ["commit 5", "commit 2", "commit 1"])
        let squashed = try git(["log", "-1", "--format=%B", "HEAD~1"])
        #expect(squashed.contains("commit 2") && squashed.contains("commit 3") && squashed.contains("commit 4"))
        #expect(try git(["ls-files"]).split(separator: "\n").count == 5)

        #expect(vm.undoManager?.undoDescription == "Squash 3 Commits")
        try await vm.undoManager?.undo()
        #expect(try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) == oldHead)
    }

    @Test func squashNeedsAnUnbrokenRun() async throws {
        let vm = try await loadedHistory()
        #expect(!vm.canSquash([vm.commits[0], vm.commits[2]]))
        #expect(!vm.canSquash([vm.commits[1]]))
        #expect(vm.canSquash([vm.commits[3], vm.commits[4]]))
    }

    @Test func interactiveRebaseRunsTheEditedPlan() async throws {
        let vm = try await loadedHistory()
        let base = vm.commits[4]
        let candidates = try #require(vm.rebaseCandidates(onto: base))
        #expect(candidates.map(\.summary) == ["commit 5", "commit 4", "commit 3", "commit 2"])

        let planner = InteractiveRebaseViewModel(base: base, commits: candidates)
        let steps = planner.steps
        planner.setAction(.fixup, for: steps[0])
        planner.setAction(.reword, for: steps[1])
        planner.setMessage("four, reworded", for: planner.steps[1])
        planner.setAction(.drop, for: steps[2])
        // Newest first on screen: moving "commit 2" to the top makes it replay last.
        planner.move(fromOffsets: [3], toOffset: 0)
        #expect(planner.problem == nil)

        var stopped = false
        vm.onRebaseStopped = { stopped = true }
        await vm.rebaseInteractively(onto: base, plan: planner.plan)
        #expect(vm.errorMessage == nil)
        #expect(!stopped)
        let subjects = try git(["log", "--format=%s"]).split(separator: "\n")
        #expect(subjects == ["commit 2", "four, reworded", "commit 1"])
        let files = try git(["ls-files"])
        #expect(!files.contains("f3.txt") && files.contains("f5.txt"))
        #expect(vm.undoManager?.undoDescription == "Interactive Rebase")
    }

    @Test func conflictLeavesTheRebaseStoppedForTheBanner() async throws {
        try write("x.txt", "one\n")
        try commitAll("add x")
        try write("x.txt", "two\n")
        try commitAll("change x")
        let vm = try await loadedHistory()
        let base = vm.commits[2]
        let planner = InteractiveRebaseViewModel(base: base, commits: try #require(vm.rebaseCandidates(onto: base)))
        planner.move(fromOffsets: [1], toOffset: 0)

        var stopped = false
        vm.onRebaseStopped = { stopped = true }
        await vm.rebaseInteractively(onto: base, plan: planner.plan)
        #expect(stopped)
        #expect(vm.pendingAction == nil)
        #expect(vm.errorMessage == GitRepositoryError.rebaseStopped.errorDescription)
        #expect(vm.repository.repositoryState == .rebaseInteractive)
        try await vm.repository.abortRebase()
    }

    @Test func invalidPlanNeverStartsARebase() async throws {
        let vm = try await loadedHistory()
        let head = try git(["rev-parse", "HEAD"])
        let base = vm.commits[2]
        let plan = try #require(vm.rebaseCandidates(onto: base)).reversed().map { RebaseStep(sha: $0.id, action: .fixup) }
        await vm.rebaseInteractively(onto: base, plan: plan)
        #expect(vm.errorMessage != nil)
        #expect(vm.repository.repositoryState == .normal)
        #expect(try git(["rev-parse", "HEAD"]) == head)
    }

    @Test func planRejectsFoldingTheFirstCommit() {
        let steps = [RebaseStep(sha: "a", action: .drop), RebaseStep(sha: "b", action: .fixup)]
        #expect(RebasePlan.problem(with: steps) != nil)
        #expect(RebasePlan.todo([RebaseStep(sha: "a", action: .drop)]) { _ in nil } == "noop\n")
        let reword = RebaseStep(sha: "a", action: .reword, message: "m")
        #expect(RebasePlan.todo([reword]) { _ in "'/tmp/m'" } == "pick a\nexec git commit --amend --no-verify --allow-empty -q -F '/tmp/m'\n")
    }

    // MARK: Helpers

    private func write(_ file: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(file))
    }

    private func commitAll(_ message: String) throws {
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", message])
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text
    }
}
