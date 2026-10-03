// SidebarDropTests.swift
// GroveTests
//
// Sidebar drag and drop: which action a drop asks to confirm, and what each does, against a scratch clone and bare remote.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct SidebarDropTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "--bare", "-b", "main", "origin.git"])
        try git(["clone", "-q", "origin.git", "a"])
        for clone in ["a"] {
            try git(["config", "user.name", "Tester"], in: clone)
            try git(["config", "user.email", "tester@example.com"], in: clone)
            try git(["config", "commit.gpgsign", "false"], in: clone)
        }
        try commit("a", file: "base.txt", message: "initial")
        try git(["push", "-q", "-u", "origin", "main"], in: "a")
    }

    private func makeSidebar() async throws -> SidebarViewModel {
        let vm = SidebarViewModel(repository: try await GitRepository(path: root.appendingPathComponent("a")))
        await vm.refresh()
        return vm
    }

    @Test func dropsResolveToTheRightAction() async throws {
        try git(["branch", "feature"], in: "a")
        try git(["fetch", "-q"], in: "a")
        let vm = try await makeSidebar()
        let main = try #require(vm.localBranches.first { $0.name == "main" })

        #expect(vm.handleDrop("feature", onBranch: main, option: false))
        #expect(vm.pendingDrop == .merge(source: "feature", target: "main"))
        #expect(vm.handleDrop("feature", onBranch: main, option: true))
        #expect(vm.pendingDrop == .rebase(target: "main", onto: "feature"))
        #expect(vm.handleDrop("origin/main", onBranch: main, option: false))
        #expect(vm.pendingDrop == .pull(remoteBranch: "origin/main", target: "main"))
        #expect(!vm.handleDrop("main", onBranch: main, option: false))
        #expect(!vm.handleDrop("v1.0", onBranch: main, option: false))

        let origin = try #require(vm.remotes.first)
        #expect(vm.handleDrop("feature", onRemote: origin))
        #expect(vm.pendingDrop == .push(branch: "feature", remote: "origin"))
        #expect(!vm.handleDrop("origin/main", onRemote: origin))
    }

    @Test func mergeIntoABranchThatIsNotCheckedOut() async throws {
        try git(["checkout", "-q", "-b", "feature"], in: "a")
        try commit("a", file: "feature.txt", message: "feature work")
        try git(["checkout", "-q", "-b", "other", "main"], in: "a")
        let vm = try await makeSidebar()

        vm.requestDrop(.merge(source: "feature", target: "main"))
        await vm.confirmDrop()

        #expect(vm.pendingDrop == nil && vm.dropError == nil)
        #expect(try git(["rev-parse", "--abbrev-ref", "HEAD"], in: "a") == "main")
        #expect(try git(["log", "-1", "--format=%s", "main"], in: "a") == "feature work")
    }

    @Test func pullFastForwardsABranchThatIsNotCheckedOut() async throws {
        try git(["clone", "-q", "origin.git", "b"])
        try git(["config", "user.name", "Other"], in: "b")
        try git(["config", "user.email", "other@example.com"], in: "b")
        try git(["config", "commit.gpgsign", "false"], in: "b")
        try commit("b", file: "remote.txt", message: "from b")
        try git(["push", "-q", "origin", "main"], in: "b")
        try git(["checkout", "-q", "-b", "side"], in: "a")
        try git(["fetch", "-q"], in: "a")
        let vm = try await makeSidebar()

        vm.requestDrop(.pull(remoteBranch: "origin/main", target: "main"))
        await vm.confirmDrop()

        #expect(vm.dropError == nil)
        #expect(try git(["log", "-1", "--format=%s", "main"], in: "a") == "from b")
        #expect(try git(["rev-parse", "--abbrev-ref", "HEAD"], in: "a") == "side")
    }

    @Test func pushSendsALocalBranchUnderAnotherName() async throws {
        try git(["checkout", "-q", "-b", "topic"], in: "a")
        try commit("a", file: "topic.txt", message: "topic work")
        try git(["checkout", "-q", "main"], in: "a")
        let vm = try await makeSidebar()

        vm.requestDrop(.push(branch: "topic", remote: "origin"))
        await vm.confirmDrop(remoteBranchName: "review/topic", setUpstream: true)

        #expect(vm.dropError == nil)
        #expect(try git(["log", "-1", "--format=%s", "review/topic"], in: "origin.git") == "topic work")
        #expect(try git(["rev-parse", "--abbrev-ref", "topic@{u}"], in: "a") == "origin/review/topic")
    }

    @Test func failedDropKeepsTheSheetWithTheError() async throws {
        try git(["checkout", "-q", "-b", "diverged"], in: "a")
        try commit("a", file: "mine.txt", message: "mine")
        try git(["checkout", "-q", "main"], in: "a")
        try commit("a", file: "theirs.txt", message: "theirs")
        try git(["push", "-q", "origin", "main"], in: "a")
        try git(["checkout", "-q", "-b", "elsewhere"], in: "a")
        let vm = try await makeSidebar()

        vm.requestDrop(.pull(remoteBranch: "origin/main", target: "diverged"))
        await vm.confirmDrop()

        #expect(vm.pendingDrop != nil)
        #expect(vm.dropError != nil)
    }

    // MARK: Helpers

    private func commit(_ clone: String, file: String, message: String) throws {
        try Data(message.utf8).write(to: root.appendingPathComponent(clone).appendingPathComponent(file))
        try git(["add", "."], in: clone)
        try git(["commit", "-q", "-m", message], in: clone)
    }

    @discardableResult
    private func git(_ args: [String], in directory: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory.map { root.appendingPathComponent($0) } ?? root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
