// MockGitRepositoryTests.swift
// GroveKitTests
//
// Smoke tests that verify MockGitRepository returns valid, non-crashing
// data for all read operations that ViewModels rely on.
// All tests run on MainActor because MockGitRepository is @MainActor.

import Foundation
import Testing
@testable import GroveKit

// MARK: - MockGitRepositoryTests

@MainActor
struct MockGitRepositoryTests {

    // MARK: Status

    @Test func mockRepository_status_returnsNonEmptyEntries() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.status()
        #expect(!entries.isEmpty)
    }

    @Test func mockRepository_status_entriesHaveNonEmptyPaths() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.status()
        for entry in entries {
            #expect(!entry.path.isEmpty, "StatusEntry path must not be empty")
        }
    }

    @Test func mockRepository_status_idMatchesPath() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.status()
        for entry in entries {
            #expect(entry.id == entry.path)
        }
    }

    // MARK: Log

    @Test func mockRepository_log_returnsCommits() async throws {
        let repo = MockGitRepository()
        let commits = try await repo.log(maxCount: 10, skip: 0, branch: nil)
        #expect(!commits.isEmpty)
    }

    @Test func mockRepository_log_commitsHaveValidSHAs() async throws {
        let repo = MockGitRepository()
        let commits = try await repo.log(maxCount: 20, skip: 0, branch: nil)
        for commit in commits {
            #expect(commit.id.count == 40, "SHA must be 40 characters: \(commit.id)")
        }
    }

    @Test func mockRepository_log_commitsHaveNonEmptySummaries() async throws {
        let repo = MockGitRepository()
        let commits = try await repo.log(maxCount: 20, skip: 0, branch: nil)
        for commit in commits {
            #expect(!commit.summary.isEmpty, "Summary must not be empty for \(commit.id)")
        }
    }

    @Test func mockRepository_log_maxCountRespected() async throws {
        let repo = MockGitRepository()
        let commits = try await repo.log(maxCount: 3, skip: 0, branch: nil)
        #expect(commits.count <= 3)
    }

    @Test func mockRepository_log_skipRespected() async throws {
        let repo = MockGitRepository()
        let allCommits  = try await repo.log(maxCount: 100, skip: 0, branch: nil)
        let skipped = try await repo.log(maxCount: 100, skip: 2, branch: nil)
        #expect(skipped.count == max(0, allCommits.count - 2))
    }

    // MARK: Local Branches

    @Test func mockRepository_localBranches_returnsNonEmpty() async throws {
        let repo = MockGitRepository()
        let branches = try await repo.localBranches()
        #expect(!branches.isEmpty)
    }

    @Test func mockRepository_localBranches_allAreLocal() async throws {
        let repo = MockGitRepository()
        let branches = try await repo.localBranches()
        for branch in branches {
            #expect(branch.isLocal, "Branch \(branch.name) should be local")
            #expect(!branch.isRemote, "Branch \(branch.name) must not be remote")
        }
    }

    @Test func mockRepository_localBranches_haveNonEmptyNames() async throws {
        let repo = MockGitRepository()
        let branches = try await repo.localBranches()
        for branch in branches {
            #expect(!branch.name.isEmpty)
        }
    }

    @Test func mockRepository_localBranches_exactlyOneIsHEAD() async throws {
        let repo = MockGitRepository()
        let branches = try await repo.localBranches()
        let headBranches = branches.filter(\.isHEAD)
        #expect(headBranches.count == 1)
    }

    // MARK: Remote Branches

    @Test func mockRepository_remoteBranches_allAreRemote() async throws {
        let repo = MockGitRepository()
        let branches = try await repo.remoteBranches()
        for branch in branches {
            #expect(branch.isRemote, "Branch \(branch.name) should be remote")
            #expect(!branch.isLocal, "Branch \(branch.name) must not be local")
        }
    }

    @Test func mockRepository_remoteBranches_haveRemoteName() async throws {
        let repo = MockGitRepository()
        let branches = try await repo.remoteBranches()
        for branch in branches {
            #expect(branch.remoteName != nil, "Remote branch \(branch.name) must have remoteName")
        }
    }

    // MARK: currentBranch

    @Test func mockRepository_currentBranchMatchesHEADBranch() async throws {
        let repo = MockGitRepository()
        let localBranches = try await repo.localBranches()
        let headBranch = localBranches.first(where: \.isHEAD)
        #expect(repo.currentBranch?.name == headBranch?.name)
    }

    // MARK: Stashes

    @Test func mockRepository_stashes_returnsEntries() async throws {
        let repo = MockGitRepository()
        let stashes = try await repo.stashes()
        #expect(!stashes.isEmpty)
    }

    @Test func mockRepository_stashes_indicesAreUnique() async throws {
        let repo = MockGitRepository()
        let stashes = try await repo.stashes()
        let ids = stashes.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    // MARK: Tags

    @Test func mockRepository_tags_returnsEntries() async throws {
        let repo = MockGitRepository()
        let tags = try await repo.tags()
        #expect(!tags.isEmpty)
    }

    @Test func mockRepository_tags_haveNonEmptyNames() async throws {
        let repo = MockGitRepository()
        let tags = try await repo.tags()
        for tag in tags {
            #expect(!tag.name.isEmpty)
        }
    }

    // MARK: Remotes

    @Test func mockRepository_remotes_returnsEntries() async throws {
        let repo = MockGitRepository()
        let remotes = try await repo.remotes()
        #expect(!remotes.isEmpty)
    }

    @Test func mockRepository_remotes_haveNonEmptyURLs() async throws {
        let repo = MockGitRepository()
        let remotes = try await repo.remotes()
        for remote in remotes {
            #expect(!remote.url.isEmpty)
        }
    }

    // MARK: Blame

    @Test func mockRepository_blame_returnsEntries() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.blame(file: "Sources/App/Main.swift", revision: nil)
        #expect(!entries.isEmpty)
    }

    @Test func mockRepository_blame_entriesHaveNonZeroLineCount() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.blame(file: "Sources/App/Main.swift", revision: nil)
        for entry in entries {
            #expect(entry.lineCount > 0)
        }
    }

    // MARK: Reflog

    @Test func mockRepository_reflog_returnsEntries() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.reflog(maxCount: 10)
        #expect(!entries.isEmpty)
    }

    @Test func mockRepository_reflog_maxCountRespected() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.reflog(maxCount: 3)
        #expect(entries.count <= 3)
    }

    // MARK: Diff

    @Test func mockRepository_diffForFirstStatusEntry_doesNotCrash() async throws {
        let repo = MockGitRepository()
        let entries = try await repo.status()
        guard let first = entries.first else { return }
        let diff = try await repo.diff(for: first, staged: false)
        #expect(diff.filePath == first.path)
    }

    @Test func mockRepository_diffForCommit_returnsFileDiffs() async throws {
        let repo = MockGitRepository()
        let commits = try await repo.log(maxCount: 1, skip: 0, branch: nil)
        guard let commit = commits.first else { return }
        let diffs = try await repo.diffForCommit(commit.id)
        #expect(!diffs.isEmpty)
    }

    // MARK: repository properties

    @Test func mockRepository_displayNameIsNotEmpty() {
        let repo = MockGitRepository()
        #expect(!repo.displayName.isEmpty)
    }

    @Test func mockRepository_pathIsAbsolute() {
        let repo = MockGitRepository()
        #expect(repo.path.path.hasPrefix("/"))
    }

    @Test func mockRepository_repositoryStateIsNormalByDefault() {
        let repo = MockGitRepository()
        #expect(repo.repositoryState == .normal)
    }
}
