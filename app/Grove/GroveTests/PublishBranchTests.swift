// PublishBranchTests.swift
// GroveTests
//
// The git side of creating pull requests and remote repositories, on a throwaway fixture with a local origin.

import Foundation
import Testing
@testable import Grove

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
        let repo = try await GitRepository(path: fixture.repo)
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
        let repo = try await GitRepository(path: fixture.repo)
        #expect(await repo.defaultBranch(of: "origin") == head)
        #expect(await repo.defaultBranch(of: "nowhere") == nil)
    }

    @Test func addRemoteRegistersTheURL() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let repo = try await GitRepository(path: fixture.repo)
        try await repo.addRemote(name: "github", url: "git@github.com:example/new.git")
        #expect(try await repo.remotes().contains { $0.name == "github" && $0.url == "git@github.com:example/new.git" })
        await #expect(throws: (any Error).self) { try await repo.addRemote(name: "github", url: "x") }
    }
}
