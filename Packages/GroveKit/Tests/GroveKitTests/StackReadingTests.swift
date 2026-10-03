// StackReadingTests.swift
// GroveKitTests
//
// Stacks built with plain git in a scratch repository, recognized end to end with no Grove config present.

import Foundation
import Testing
@testable import GroveKit

/// A scratch repository under the temporary directory, driven with `/usr/bin/git`.
struct ScratchRepository {
    let root: URL

    init(_ name: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try commit("base.txt", "base\n", "base")
    }

    func commit(_ file: String, _ text: String, _ message: String, in directory: URL? = nil) throws {
        let folder = directory ?? root
        try Data(text.utf8).write(to: folder.appendingPathComponent(file))
        try git(["add", "-A"], in: folder)
        try git(["commit", "-q", "-m", message], in: folder)
    }

    func sha(_ revision: String) throws -> String {
        try git(["rev-parse", revision]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func git(_ args: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory ?? root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(bytes: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 { throw GitShellError.nonZeroExit(command: args.first ?? "", exitCode: process.terminationStatus, stderr: text) }
        return text
    }
}

@MainActor
@Suite(.serialized)
struct StackReadingTests {

    /// main → a → b → c, plus b → d checked out in a linked worktree.
    private func buildStack() throws -> ScratchRepository {
        let repo = try ScratchRepository("stack")
        try repo.git(["checkout", "-q", "-b", "a"])
        try repo.commit("a.txt", "a\n", "a1")
        try repo.git(["checkout", "-q", "-b", "b"])
        try repo.commit("b.txt", "b\n", "b1")
        try repo.git(["checkout", "-q", "-b", "c"])
        try repo.commit("c.txt", "c\n", "c1")
        try repo.git(["branch", "d", "b"])
        let worktree = repo.root.appendingPathExtension("d")
        try repo.git(["worktree", "add", "-q", worktree.path, "d"])
        try repo.commit("d.txt", "d\n", "d1", in: worktree)
        try repo.git(["checkout", "-q", "main"])
        return repo
    }

    private func refs(_ repo: ScratchRepository) async throws -> RepositoryRefs {
        let refs = RepositoryRefs(repository: try await GitRepository(path: repo.root, runner: LocalGitRunner()))
        await refs.refresh()
        return refs
    }

    @Test func plainGitStackIsRecognizedWithoutConfig() async throws {
        let repo = try buildStack()
        #expect(throws: (any Error).self) { try repo.git(["config", "--get-regexp", "grove"]) }
        let refs = try await refs(repo)
        #expect(refs.trunk == "main")
        #expect(refs.stacks.count == 1)
        let stack = try #require(refs.stacks.first)
        #expect(stack.layers.map(\.branch) == ["a", "b", "c", "d"])
        #expect(stack.children(of: "b").map(\.branch) == ["c", "d"])
        #expect(stack.layer("d")?.worktreePath?.hasSuffix(".d") == true)
        #expect(stack.layers.allSatisfy { !$0.health.contains(.needsRestack) })
    }

    @Test func amendedRootMarksItsChildForRestack() async throws {
        let repo = try buildStack()
        try repo.git(["checkout", "-q", "a"])
        try Data("a amended\n".utf8).write(to: repo.root.appendingPathComponent("a.txt"))
        try repo.git(["commit", "-q", "-a", "--amend", "-m", "a1 amended"])
        try repo.git(["checkout", "-q", "main"])
        try repo.commit("main.txt", "more\n", "main moves on")

        let stack = try #require(try await refs(repo).stacks.first)
        #expect(stack.layers.map(\.branch) == ["a", "b", "c", "d"])
        let b = try #require(stack.layer("b"))
        #expect(b.parent == "a")
        #expect(b.health.contains(.needsRestack))
        #expect(b.commits.count == 1)
        #expect(b.base == (try repo.sha("a@{1}")))
        #expect(stack.trunkAhead == 1)
    }
}
