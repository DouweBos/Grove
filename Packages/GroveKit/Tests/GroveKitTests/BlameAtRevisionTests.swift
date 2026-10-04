// BlameAtRevisionTests.swift
// GroveKitTests
//
// Blaming a file at any ref, including one off HEAD's line, against a scratch repository.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct BlameAtRevisionTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grovekit-blame-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
    }

    @Test func blamesABranchOffHEADsLine() async throws {
        try commit("a.txt", "one\n", "add a")
        try git(["switch", "-q", "-c", "side"])
        try commit("a.txt", "one\nside\n", "side change")
        try git(["switch", "-q", "main"])
        try commit("a.txt", "one\nmain\n", "main change")

        let vm = BlameViewModel(repository: try await GitRepository(path: root, runner: LocalGitRunner()))
        await vm.open(file: "a.txt", revision: "side")
        #expect(vm.revision == "side")
        #expect(vm.lines.map(\.text) == ["one", "side"])
        #expect(vm.lines.last?.entry?.summary == "side change")

        await vm.open(file: "a.txt")
        #expect(vm.isAtWorkingTree)
        #expect(vm.lines.map(\.text) == ["one", "main"])
    }

    @Test func unknownRefShowsGitsError() async throws {
        try commit("a.txt", "one\n", "add a")
        let vm = BlameViewModel(repository: try await GitRepository(path: root, runner: LocalGitRunner()))
        await vm.open(file: "a.txt", revision: "nope")
        #expect(vm.lines.isEmpty)
        #expect(vm.errorMessage?.contains("earlier revision") == false)
    }

    // MARK: Helpers

    private func commit(_ file: String, _ text: String, _ message: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(file))
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", message])
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
