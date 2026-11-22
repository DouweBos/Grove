// GitCommandOptionsTests.swift
// GroveKitTests
//
// The options hosts rely on, run through the default commands on scratch repositories.

import Foundation
@testable import GroveKit
import Testing

@MainActor
@Suite(.serialized)
struct GitCommandOptionsTests {

    private let root: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-options-\(UUID().uuidString)")
        root = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "--bare", "../origin.git"])
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try git(["config", "tag.gpgsign", "false"])
        try commit("a.txt", "one\n")
        try git(["remote", "add", "origin", "../origin.git"])
        try git(["push", "-q", "-u", "origin", "main"])
    }

    private func commands() async throws -> RepositoryCommands {
        RepositoryCommands(repository: try await GitRepository(path: root, runner: LocalGitRunner()))
    }

    @Test func squashMergeStagesWithoutCommitting() async throws {
        try git(["switch", "-q", "-c", "topic"])
        try commit("b.txt", "topic\n")
        try git(["switch", "-q", "main"])
        let head = try git(["rev-parse", "HEAD"])
        try await commands().perform(.merge("topic", squash: true))
        #expect(try git(["rev-parse", "HEAD"]) == head)
        #expect(try git(["diff", "--cached", "--name-only"]) == "b.txt")
    }

    @Test func keepIndexLeavesWhatIsStaged() async throws {
        try write("a.txt", "staged\n")
        try git(["add", "a.txt"])
        try await commands().perform(.stash(message: "wip", includeUntracked: false, keepIndex: true, paths: nil))
        #expect(try git(["diff", "--cached", "--name-only"]) == "a.txt")
        #expect(try git(["stash", "list"]).contains("wip"))
    }

    @Test func stashBecomesABranch() async throws {
        try write("a.txt", "stashed\n")
        try git(["stash", "push", "-q"])
        try await commands().perform(.branchFromStash(index: 0, name: "saved"))
        #expect(try git(["branch", "--show-current"]) == "saved")
        #expect(try git(["diff", "--name-only"]) == "a.txt")
        #expect(try git(["stash", "list"]).isEmpty)
    }

    @Test(arguments: [(PushTags.none, ""), (.follow, "annotated"), (.all, "annotated\nlight")])
    func pushTakesTheTagsAskedFor(tags: PushTags, expected: String) async throws {
        try commit("b.txt", "two\n")
        try git(["tag", "-a", "annotated", "-m", "release"])
        try git(["tag", "light"])
        try await commands().perform(.push(remote: "origin", branch: "main", forceWithLease: false, setUpstream: false,
                                           options: PushOptions(tags: tags)))
        #expect(try git(["--git-dir=../origin.git", "tag"]) == expected)
    }

    @Test func remotesRenameAndPrune() async throws {
        try git(["push", "-q", "origin", "main:gone"])
        let commands = try await commands()
        try await commands.perform(.renameRemote(from: "origin", to: "upstream"))
        #expect(try git(["remote"]) == "upstream")
        try git(["--git-dir=../origin.git", "update-ref", "-d", "refs/heads/gone"])
        try await commands.perform(.pruneRemote("upstream"))
        #expect(try git(["for-each-ref", "--format=%(refname)", "refs/remotes/upstream/gone"]).isEmpty)
    }

    private func write(_ file: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(file))
    }

    private func commit(_ file: String, _ text: String) throws {
        try write(file, text)
        try git(["add", file])
        try git(["commit", "-q", "-m", file])
    }

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
