// PatchTests.swift
// GroveTests
//
// Create Patch and Apply Patch from the Changes tab, against a scratch repository.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct PatchTests {

    private let root: URL
    private let patchFile: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-patch-\(UUID().uuidString)")
        root = base.appendingPathComponent("repo")
        patchFile = base.appendingPathComponent("changes.patch")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try write("a.txt", "one\ntwo\nthree\n")
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", "initial"])
    }

    @Test func roundTripsUnstagedChangesIncludingNewFiles() async throws {
        try write("a.txt", "one\nTWO\nthree\n")
        try write("new.txt", "brand new\n")
        let repo = try await GitRepository(path: root)
        let vm = WorkingCopyViewModel(repository: repo)
        await vm.refresh()
        await vm.createPatch(from: vm.unstagedFiles, side: .unstaged, to: patchFile)
        #expect(vm.errorMessage == nil)

        try git(["checkout", "--", "a.txt"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("new.txt"))
        await vm.beginApplyPatch(patchFile)
        #expect(vm.patchApply?.check == .applies)
        await vm.setPatchAppliesToIndex(true)
        #expect(vm.patchApply?.check == .applies)
        await vm.applyPendingPatch()

        #expect(vm.patchApply == nil)
        #expect(try read("a.txt") == "one\nTWO\nthree\n")
        #expect(try read("new.txt") == "brand new\n")
        #expect(Set(vm.stagedFiles.map(\.path)) == ["a.txt", "new.txt"])
    }

    @Test func checkReportsWhyAPatchDoesNotApply() async throws {
        try write("a.txt", "one\nTWO\nthree\n")
        let repo = try await GitRepository(path: root)
        let vm = WorkingCopyViewModel(repository: repo)
        await vm.refresh()
        await vm.createPatch(from: vm.unstagedFiles, side: .unstaged, to: patchFile)
        try write("a.txt", "something else entirely\n")

        await vm.beginApplyPatch(patchFile)
        guard case .fails(let message) = vm.patchApply?.check else {
            Issue.record("Expected the check to fail")
            return
        }
        #expect(message.contains("a.txt"))
        await vm.applyPendingPatch()
        #expect(try read("a.txt") == "something else entirely\n")
    }

    @Test func stagedPatchOnlyHoldsStagedChanges() async throws {
        try write("a.txt", "one\nTWO\nthree\n")
        try git(["add", "a.txt"])
        try write("a.txt", "one\nTWO\nTHREE\n")
        let repo = try await GitRepository(path: root)
        let patch = try await repo.patch(paths: ["a.txt"], staged: true)
        #expect(patch.contains("+TWO"))
        #expect(!patch.contains("+THREE"))
    }

    // MARK: Helpers

    private func write(_ file: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(file))
    }

    private func read(_ file: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
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
