// FixtureTests.swift
// GroveTests
//
// The fixture generator builds what it promises, reproducibly, and Grove reads each state correctly.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct FixtureTests {

    /// Small enough to build in well under a second.
    private static func tiny(_ spec: inout FixtureSpec) {
        (spec.commits, spec.files, spec.branches, spec.remoteBranches, spec.tags) = (80, 20, 6, 8, 12)
    }

    @Test func sameSeedGivesSameHistory() throws {
        let first = try Fixture.make(customize: Self.tiny)
        let second = try Fixture.make(customize: Self.tiny)
        let other = try Fixture.make(seed: 2, customize: Self.tiny)
        defer { [first, second, other].forEach { $0.remove() } }
        let refs = ["for-each-ref", "--format=%(refname) %(objectname)"]
        #expect(try first.git(refs) == second.git(refs))
        #expect(try first.git(["rev-parse", "HEAD"]) != other.git(["rev-parse", "HEAD"]))
    }

    @Test func historyHasTheRequestedShape() async throws {
        let fixture = try Fixture.make(customize: {
            Self.tiny(&$0)
            ($0.worktrees, $0.submodules) = (2, 1)
        })
        defer { fixture.remove() }
        #expect(fixture.result.commits >= 80)
        #expect(fixture.result.localBranches == 6)
        #expect(fixture.result.tags == 12)
        #expect(Int(try fixture.git(["rev-list", "--merges", "--count", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines))! > 0)

        let repo = try await GitRepository(path: fixture.repo)
        let local = try await repo.localBranches()
        #expect(local.contains { $0.upstream != nil && !$0.isHEAD }, "Pushed branches track origin")
        #expect(local.contains { $0.upstream == nil }, "Some branches were never pushed")
        let worktrees = try await repo.worktrees()
        #expect(worktrees.count == 3)
        #expect(try fixture.git(["submodule", "status"]).contains("libs/shared-0"))
    }

    @Test func mergeConflictLeavesAConflictedMerge() async throws {
        let fixture = try Fixture.make(states: [.mergeConflict], customize: Self.tiny)
        defer { fixture.remove() }
        let repo = try await GitRepository(path: fixture.repo)
        #expect(repo.repositoryState == .merge)
        let status = try await repo.status()
        #expect(status.contains { $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted })
        #expect(status.contains { $0.indexStatus == .modified }, "The clean half of the merge is staged")
    }

    @Test func rebaseConflictStopsMidRebase() async throws {
        let fixture = try Fixture.make(states: [.rebaseConflict, .dirty(5)], customize: Self.tiny)
        defer { fixture.remove() }
        let repo = try await GitRepository(path: fixture.repo)
        #expect(repo.repositoryState == .rebase || repo.repositoryState == .rebaseInteractive)
        #expect(try await repo.status().contains { $0.workdirStatus == .conflicted || $0.indexStatus == .conflicted })
    }

    @Test func dirtyStashesAndDetached() async throws {
        let fixture = try Fixture.make(states: [.dirty(20), .stashes(3), .detached], customize: Self.tiny)
        defer { fixture.remove() }
        let repo = try await GitRepository(path: fixture.repo)
        let status = try await repo.status()
        #expect(status.contains { $0.workdirStatus == .untracked })
        #expect(status.contains { $0.indexStatus == .modified })
        #expect(status.contains { $0.workdirStatus == .modified })
        #expect(status.contains { $0.indexStatus == .deleted })
        #expect(try await repo.stashes().count == 3)
        #expect(try fixture.git(["branch", "--show-current"]).isEmpty)
    }

    @Test func divergedAndMissingWorktree() async throws {
        let fixture = try Fixture.make(states: [.diverged, .missingWorktree], customize: Self.tiny)
        defer { fixture.remove() }
        let repo = try await GitRepository(path: fixture.repo)
        let main = try #require(try await repo.localBranches().first { $0.name == "main" })
        #expect(main.ahead == 2)
        #expect(main.behind == 3)
        #expect(try await repo.worktrees().contains(where: \.isPrunable))
    }

    @Test func noUpstreamLargeFileAndImage() async throws {
        let fixture = try Fixture.make(states: [.noUpstream, .largeFile, .binaryImage], customize: Self.tiny)
        defer { fixture.remove() }
        let repo = try await GitRepository(path: fixture.repo)
        let current = try #require(try await repo.localBranches().first(where: \.isHEAD))
        #expect(current.upstream == nil)
        let changed = Set(try await repo.status().map(\.path))
        #expect(changed == ["data/catalog.json", "assets/artwork.png"])
        let png = try Data(contentsOf: fixture.repo.appendingPathComponent("assets/artwork.png"))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
