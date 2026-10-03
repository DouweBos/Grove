// PublishBranchTests.swift
// GroveKitTests
//
// The git side of creating pull requests and remote repositories, on a throwaway fixture with a local origin.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct PublishBranchTests {

    private func fixture() throws -> Fixture {
        try Fixture.make { ($0.commits, $0.files, $0.branches, $0.remoteBranches, $0.tags) = (30, 8, 4, 3, 0) }
    }

    @Test func publishingPushesAndTracksABranchThatIsNotCheckedOut() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        _ = try fixture.git(["branch", "grove-publish-test"])
        let repo = try await GitRepository(path: fixture.repo, runner: LocalGitRunner())
        try await repo.publishBranch("grove-publish-test", to: "origin", as: "grove-published")
        #expect(try fixture.git(["rev-parse", "--abbrev-ref", "grove-publish-test@{upstream}"])
            .trimmingCharacters(in: .whitespacesAndNewlines) == "origin/grove-published")
        #expect(!(try fixture.git(["branch", "--list", "grove-published"], in: fixture.origin)).isEmpty)
    }

    @Test func defaultBranchFollowsTheRemoteHead() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let head = try fixture.git(["symbolic-ref", "--short", "HEAD"], in: fixture.origin).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try fixture.git(["remote", "set-head", "origin", head])
        let repo = try await GitRepository(path: fixture.repo, runner: LocalGitRunner())
        #expect(await repo.defaultBranch(of: "origin") == head)
        #expect(await repo.defaultBranch(of: "nowhere") == nil)
    }

    @Test func addRemoteRegistersTheURL() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let repo = try await GitRepository(path: fixture.repo, runner: LocalGitRunner())
        try await repo.addRemote(name: "github", url: "git@github.com:example/new.git")
        #expect(try await repo.remotes().contains { $0.name == "github" && $0.url == "git@github.com:example/new.git" })
        await #expect(throws: (any Error).self) { try await repo.addRemote(name: "github", url: "x") }
    }

    @Test func streamingCloneReportsProgressAndCancelStopsTheProcess() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let target = fixture.repo.deletingLastPathComponent().appendingPathComponent("streamed-clone")
        let chunks = LockedStrings()
        try await GitShell(workingDirectory: fixture.repo.deletingLastPathComponent(), runner: LocalGitRunner())
            .runStreaming(["clone", "--progress", "file://\(fixture.origin.path)", target.path]) { chunks.append($0) }
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent(".git").path))
        #expect(chunks.joined.contains("Cloning into"))

        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        let started = Date()
        let task = Task { try await ProcessRunner.runStreaming(sleeper) { _ in } }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        _ = try? await task.value
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

/// Collects streamed chunks from a background reader.
private final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.withLock { values.append(value) } }
    var joined: String { lock.withLock { values.joined() } }
}
