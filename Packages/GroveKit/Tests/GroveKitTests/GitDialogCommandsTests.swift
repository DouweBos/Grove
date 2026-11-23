// GitDialogCommandsTests.swift
// GroveKitTests
//
// The commands the shared dialogs added, run through the default commands on scratch repositories.

import Foundation
@testable import GroveKit
import Testing

@MainActor
@Suite(.serialized)
final class GitDialogCommandsTests {

    private let base: URL
    private let root: URL

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-dialog-commands-\(UUID().uuidString)")
        root = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "--bare", "-b", "main", "../origin.git"])
        try git(["init", "-q", "--bare", "-b", "main", "../fork.git"])
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try git(["config", "tag.gpgsign", "false"])
        try commit("a.txt", "one\n")
        try git(["remote", "add", "origin", "../origin.git"])
        try git(["push", "-q", "-u", "origin", "main"])
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    private func commands() async throws -> RepositoryCommands {
        RepositoryCommands(repository: try await GitRepository(path: root, runner: LocalGitRunner()))
    }

    @Test func fetchingWithoutARemoteFetchesEveryRemote() async throws {
        try git(["remote", "add", "fork", "../fork.git"])
        try git(["push", "-q", "fork", "main:forked"])
        try git(["push", "-q", "origin", "main:shared"])
        try git(["update-ref", "-d", "refs/remotes/fork/forked"])
        try git(["update-ref", "-d", "refs/remotes/origin/shared"])
        let fractions = Fractions()
        try await commands().perform(.fetch(remote: nil)) { value in Task { @MainActor in fractions.values.append(value) } }
        let remotes = try git(["for-each-ref", "--format=%(refname:short)", "refs/remotes"])
        #expect(remotes.contains("fork/forked") && remotes.contains("origin/shared"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(fractions.values.allSatisfy { (0...1).contains($0) })
    }

    @Test func aBranchThatIsNotCheckedOutPushesWithItsOptions() async throws {
        try git(["branch", "topic"])
        try git(["switch", "-q", "topic"])
        try commit("b.txt", "topic\n")
        try git(["tag", "-a", "v1", "-m", "release"])
        try git(["switch", "-q", "main"])
        try await commands().perform(.pushBranch("topic", remote: "origin", as: "review", forceWithLease: false,
                                                 setUpstream: true, options: PushOptions(tags: .follow)))
        #expect(try git(["--git-dir=../origin.git", "rev-parse", "review"]) == git(["rev-parse", "topic"]))
        #expect(try git(["--git-dir=../origin.git", "tag"]) == "v1")
        #expect(try git(["rev-parse", "--abbrev-ref", "topic@{upstream}"]) == "origin/review")
        #expect(try git(["branch", "--show-current"]) == "main")
    }

    @Test func stashAndCheckoutCarriesTheChangesAcross() async throws {
        try git(["branch", "other"])
        try write("a.txt", "edited\n")
        try write("new.txt", "untracked\n")
        try await commands().perform(.stashAndCheckout("other"))
        #expect(try git(["branch", "--show-current"]) == "other")
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "edited\n")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.txt").path))
        #expect(try git(["stash", "list"]).isEmpty)
    }

    @Test func discardAndCheckoutDropsTrackedChangesOnly() async throws {
        try git(["switch", "-q", "-c", "other"])
        try commit("a.txt", "theirs\n")
        try git(["switch", "-q", "main"])
        try write("a.txt", "mine\n")
        try write("new.txt", "untracked\n")
        try await commands().perform(.discardAndCheckout("other"))
        #expect(try git(["branch", "--show-current"]) == "other")
        #expect(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "theirs\n")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.txt").path))
    }

    @Test func theCheckedOutBranchRenames() async throws {
        try await commands().perform(.renameCurrentBranch(to: "trunk"))
        #expect(try git(["branch", "--show-current"]) == "trunk")
    }

    @Test func aSnapshotWithNothingToSaveSaysSo() async throws {
        await #expect(throws: GitCommandError.nothingToSnapshot) {
            try await self.commands().perform(.snapshot(message: "empty", includeUntracked: true))
        }
        try write("a.txt", "changed\n")
        try await commands().perform(.snapshot(message: "kept", includeUntracked: true))
        #expect(try git(["stash", "list"]).contains("kept"))
        #expect(try git(["diff", "--name-only"]) == "a.txt")
    }

    @Test func syncPullsAndPushes() async throws {
        try git(["clone", "-q", "../origin.git", "../other"])
        try git(["-C", "../other", "-c", "user.name=O", "-c", "user.email=o@o", "commit", "-q", "--allow-empty", "-m", "theirs"])
        try git(["-C", "../other", "push", "-q", "origin", "main"])
        try commit("c.txt", "mine\n")
        try await commands().perform(.sync(remote: nil, strategy: .rebase))
        #expect(try git(["rev-parse", "HEAD"]) == git(["--git-dir=../origin.git", "rev-parse", "main"]))
        #expect(try git(["log", "--format=%s", "-3"]).components(separatedBy: "\n") == ["c.txt", "theirs", "a.txt"])
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

@MainActor
private final class Fractions {
    var values: [Double] = []
}
