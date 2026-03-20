// Mocks/MockGitRepository.swift
// Grove
//
// Realistic in-memory fake that conforms to GitRepositoryProtocol.
// Used by ALL view agents during Phase B development and in SwiftUI Previews.
// All methods simulate async latency with a brief Task.sleep.

import Foundation
import Observation

// MARK: - MockGitRepository

/// An in-memory fake Git repository with realistic static data.
///
/// Every ``GitRepositoryProtocol`` method returns pre-baked fake data after a
/// short artificial delay to surface any loading-state UI issues early.
@MainActor
@Observable
final class MockGitRepository: GitRepositoryProtocol {

    // MARK: Observable State

    let path: URL
    let displayName: String
    var currentBranch: BranchInfo?
    var repositoryState: RepositoryState = .normal

    // MARK: Init

    init(
        path: URL = URL(fileURLWithPath: "/Users/dev/Projects/my-app"),
        displayName: String = "my-app"
    ) {
        self.path = path
        self.displayName = displayName
        self.currentBranch = MockData.branches.first(where: { $0.isHEAD })
    }

    // MARK: Helpers

    /// Simulates a realistic async round-trip (50 ms by default).
    private func simulateLatency(_ nanoseconds: UInt64 = 50_000_000) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: Status

    func refreshStatus() async throws {
        await simulateLatency()
    }

    func status() async throws -> [StatusEntry] {
        await simulateLatency()
        return MockData.statusEntries
    }

    // MARK: Staging

    func stage(paths: [String]) async throws {
        await simulateLatency()
    }

    func unstage(paths: [String]) async throws {
        await simulateLatency()
    }

    func stageHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    func unstageHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    func stageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    func unstageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        await simulateLatency()
    }

    func stageAll() async throws {
        await simulateLatency()
    }

    func unstageAll() async throws {
        await simulateLatency()
    }

    func discardChanges(paths: [String]) async throws {
        await simulateLatency()
    }

    func discardHunk(_ hunk: HunkData, in file: String) async throws {
        await simulateLatency()
    }

    // MARK: Diff

    func diff(for entry: StatusEntry, staged: Bool) async throws -> DiffResult {
        await simulateLatency()
        return MockData.diffResult(for: entry.path)
    }

    func diffForCommit(_ sha: String) async throws -> [FileDiff] {
        await simulateLatency()
        return MockData.commitFileDiffs
    }

    // MARK: Commits

    @discardableResult
    func commit(message: String, body: String?, amend: Bool) async throws -> CommitInfo {
        await simulateLatency()
        return MockData.commits[0]
    }

    func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo] {
        await simulateLatency(30_000_000)
        let all = MockData.commits
        let start = min(skip, all.count)
        let end = min(start + maxCount, all.count)
        return Array(all[start..<end])
    }

    func commitDetail(_ sha: String) async throws -> CommitInfo {
        await simulateLatency()
        return MockData.commits.first(where: { $0.id == sha }) ?? MockData.commits[0]
    }

    // MARK: Branches

    func localBranches() async throws -> [BranchInfo] {
        await simulateLatency()
        return MockData.branches.filter(\.isLocal)
    }

    func remoteBranches() async throws -> [BranchInfo] {
        await simulateLatency()
        return MockData.branches.filter(\.isRemote)
    }

    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo {
        await simulateLatency()
        let branch = BranchInfo(
            id: "refs/heads/\(name)",
            name: name,
            isLocal: true,
            isRemote: false,
            isHEAD: checkout,
            targetSHA: MockData.commits[0].id,
            remoteName: nil,
            upstream: nil,
            ahead: 0,
            behind: 0
        )
        if checkout {
            currentBranch = branch
        }
        return branch
    }

    func checkout(branch: String) async throws {
        await simulateLatency(80_000_000)
        currentBranch = MockData.branches.first(where: { $0.name == branch })
    }

    func deleteBranch(name: String, force: Bool) async throws {
        await simulateLatency()
    }

    func deleteRemoteBranch(name: String, remote: String) async throws {
        await simulateLatency()
    }

    func renameBranch(oldName: String, newName: String) async throws {
        await simulateLatency()
    }

    // MARK: Remotes

    func remotes() async throws -> [RemoteInfo] {
        await simulateLatency()
        return MockData.remotes
    }

    func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(200_000_000)
        progress?(1.0)
    }

    func pull(remote: String?, rebase: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    func push(remote: String?, force: Bool, forceLease: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        await simulateLatency(300_000_000)
        progress?(1.0)
    }

    // MARK: Merge / Rebase

    func merge(branch: String) async throws {
        await simulateLatency(150_000_000)
    }

    func abortMerge() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    func rebase(onto: String) async throws {
        await simulateLatency(150_000_000)
    }

    func abortRebase() async throws {
        await simulateLatency()
        repositoryState = .normal
    }

    func continueRebase() async throws {
        await simulateLatency()
    }

    func conflicts() async throws -> [StatusEntry] {
        await simulateLatency()
        return MockData.statusEntries.filter { $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted }
    }

    // MARK: Stash

    func stashes() async throws -> [StashEntry] {
        await simulateLatency()
        return MockData.stashEntries
    }

    func stashCreate(message: String?, includeUntracked: Bool) async throws {
        await simulateLatency()
    }

    func stashApply(index: Int, drop: Bool) async throws {
        await simulateLatency()
    }

    func stashDrop(index: Int) async throws {
        await simulateLatency()
    }

    // MARK: Tags

    func tags() async throws -> [TagInfo] {
        await simulateLatency()
        return MockData.tags
    }

    @discardableResult
    func createTag(name: String, at sha: String?, message: String?) async throws -> TagInfo {
        await simulateLatency()
        return TagInfo(
            id: name,
            name: name,
            targetSHA: sha ?? MockData.commits[0].id,
            isAnnotated: message != nil,
            message: message,
            taggerName: "Jane Developer",
            taggerDate: Date()
        )
    }

    func deleteTag(name: String) async throws {
        await simulateLatency()
    }

    // MARK: Blame

    func blame(file: String, revision: String?) async throws -> [BlameEntry] {
        await simulateLatency(120_000_000)
        return MockData.blameEntries
    }

    // MARK: Reflog

    func reflog(maxCount: Int) async throws -> [ReflogEntry] {
        await simulateLatency()
        return Array(MockData.reflogEntries.prefix(maxCount))
    }
}

// MARK: - MockData

/// Static fake data used by ``MockGitRepository``.
///
/// All values are crafted to look realistic so that views developed against
/// the mock closely resemble what the real engine will produce.
enum MockData {

    // MARK: Authors

    static let authorJane = (name: "Jane Developer", email: "jane@example.com")
    static let authorBob  = (name: "Bob Contributor", email: "bob@example.com")
    static let authorAlice = (name: "Alice Reviewer", email: "alice@example.com")

    // MARK: Commits

    static let commits: [CommitInfo] = {
        let calendar = Calendar.current
        var result: [CommitInfo] = []

        let data: [(String, String, String?, String, [String], Bool)] = [
            // (sha, summary, body?, authorEmail, parentSHAs, isSigned)
            (
                "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
                "feat: add OAuth2 authentication flow",
                "Implements RFC 6749 authorisation code grant.\n\nIncludes PKCE extension and automatic token refresh.",
                authorJane.email,
                ["b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"],
                true
            ),
            (
                "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3",
                "refactor: split AuthManager into focused services",
                nil,
                authorJane.email,
                ["c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"],
                false
            ),
            (
                "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
                "fix: prevent token refresh race condition",
                "Multiple concurrent requests were each triggering a refresh.\nNow uses a single shared Task to serialise the refresh.",
                authorBob.email,
                ["d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"],
                false
            ),
            (
                "d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5",
                "feat: repository browser with drag-and-drop reorder",
                nil,
                authorAlice.email,
                ["e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"],
                true
            ),
            (
                "e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6",
                "Merge pull request #42 from feature/dark-mode",
                "Merges the dark mode branch into main.\n\nReviewed by Alice.",
                authorAlice.email,
                ["f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                 "06a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "feat: dark mode support for all primary views",
                nil,
                authorBob.email,
                ["16a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "16a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "chore: update SwiftLint to 0.55.1",
                nil,
                authorJane.email,
                ["26a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "26a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "test: add unit tests for CommitGraph lane algorithm",
                "Covers merge commits, cross-lane edges, and single-branch linear history.",
                authorAlice.email,
                ["36a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "36a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "perf: lazy-load commit graph rows with AsyncSequence",
                nil,
                authorJane.email,
                ["46a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "46a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "feat: hunk-level and line-level staging in diff view",
                "Implements partial patch construction using git_apply.\n\nSupports stage/unstage at hunk and individual line granularity.",
                authorBob.email,
                ["56a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                true
            ),
            (
                "56a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "fix: crash when staging empty file",
                nil,
                authorJane.email,
                ["66a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "66a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "docs: document GitRepositoryProtocol contract",
                nil,
                authorAlice.email,
                ["76a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "76a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "build: add Clibgit2 SPM package reference",
                nil,
                authorJane.email,
                ["86a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1"],
                false
            ),
            (
                "86a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1",
                "chore: initial project scaffold",
                "Bootstrap commit from WS0.\n\nEstablishes directory structure, protocols, and mocks.",
                authorJane.email,
                [],
                false
            ),
        ]

        let now = Date()
        for (index, item) in data.enumerated() {
            let (sha, summary, body, email, parents, signed) = item
            let authorName = email == authorJane.email ? authorJane.name
                           : email == authorBob.email  ? authorBob.name
                           : authorAlice.name
            let date = calendar.date(byAdding: .hour, value: -(index * 4), to: now)!
            let message = body != nil ? "\(summary)\n\n\(body!)" : summary
            result.append(CommitInfo(
                id: sha,
                message: message,
                summary: summary,
                body: body,
                authorName: authorName,
                authorEmail: email,
                authorDate: date,
                committerName: authorName,
                committerEmail: email,
                committerDate: date,
                parentIDs: parents,
                isSigned: signed
            ))
        }
        return result
    }()

    // MARK: Branches

    static let branches: [BranchInfo] = [
        BranchInfo(
            id: "refs/heads/main",
            name: "main",
            isLocal: true,
            isRemote: false,
            isHEAD: true,
            targetSHA: commits[0].id,
            remoteName: nil,
            upstream: "refs/remotes/origin/main",
            ahead: 2,
            behind: 0
        ),
        BranchInfo(
            id: "refs/heads/develop",
            name: "develop",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[3].id,
            remoteName: nil,
            upstream: "refs/remotes/origin/develop",
            ahead: 0,
            behind: 1
        ),
        BranchInfo(
            id: "refs/heads/feature/auth",
            name: "feature/auth",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[2].id,
            remoteName: nil,
            upstream: "refs/remotes/origin/feature/auth",
            ahead: 3,
            behind: 0
        ),
        BranchInfo(
            id: "refs/heads/feature/ui-overhaul",
            name: "feature/ui-overhaul",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[5].id,
            remoteName: nil,
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
        BranchInfo(
            id: "refs/heads/bugfix/crash-on-empty-stash",
            name: "bugfix/crash-on-empty-stash",
            isLocal: true,
            isRemote: false,
            isHEAD: false,
            targetSHA: commits[10].id,
            remoteName: nil,
            upstream: nil,
            ahead: 1,
            behind: 0
        ),
        // Remote branches
        BranchInfo(
            id: "refs/remotes/origin/main",
            name: "origin/main",
            isLocal: false,
            isRemote: true,
            isHEAD: false,
            targetSHA: commits[2].id,
            remoteName: "origin",
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
        BranchInfo(
            id: "refs/remotes/origin/develop",
            name: "origin/develop",
            isLocal: false,
            isRemote: true,
            isHEAD: false,
            targetSHA: commits[4].id,
            remoteName: "origin",
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
        BranchInfo(
            id: "refs/remotes/upstream/main",
            name: "upstream/main",
            isLocal: false,
            isRemote: true,
            isHEAD: false,
            targetSHA: commits[6].id,
            remoteName: "upstream",
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
    ]

    // MARK: Remotes

    static let remotes: [RemoteInfo] = [
        RemoteInfo(
            id: "origin",
            name: "origin",
            url: "git@github.com:example/my-app.git",
            pushURL: nil
        ),
        RemoteInfo(
            id: "upstream",
            name: "upstream",
            url: "https://github.com/upstream-org/my-app.git",
            pushURL: "git@github.com:upstream-org/my-app.git"
        ),
    ]

    // MARK: Tags

    static let tags: [TagInfo] = [
        TagInfo(
            id: "v1.0.0",
            name: "v1.0.0",
            targetSHA: commits[13].id,
            isAnnotated: true,
            message: "First stable release.\n\nIncludes all Phase A bootstrap work.",
            taggerName: authorJane.name,
            taggerDate: Calendar.current.date(byAdding: .day, value: -30, to: Date())
        ),
        TagInfo(
            id: "v1.1.0",
            name: "v1.1.0",
            targetSHA: commits[9].id,
            isAnnotated: true,
            message: "Adds hunk/line-level staging.",
            taggerName: authorBob.name,
            taggerDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
        ),
        TagInfo(
            id: "v1.1.1",
            name: "v1.1.1",
            targetSHA: commits[10].id,
            isAnnotated: false,
            message: nil,
            taggerName: nil,
            taggerDate: nil
        ),
    ]

    // MARK: Stash Entries

    static let stashEntries: [StashEntry] = [
        StashEntry(
            id: 0,
            message: "WIP on feature/auth: token refresh experiment",
            sha: "aa1122334455667788990011223344556677889900",
            date: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!,
            branchName: "feature/auth"
        ),
        StashEntry(
            id: 1,
            message: "WIP on main: dark mode tweaks",
            sha: "bb1122334455667788990011223344556677889900",
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            branchName: "main"
        ),
        StashEntry(
            id: 2,
            message: "On develop: experimental layout refactor",
            sha: "cc1122334455667788990011223344556677889900",
            date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            branchName: "develop"
        ),
        StashEntry(
            id: 3,
            message: "On bugfix/crash-on-empty-stash: debug logging",
            sha: "dd1122334455667788990011223344556677889900",
            date: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!,
            branchName: "bugfix/crash-on-empty-stash"
        ),
    ]

    // MARK: Status Entries

    static let statusEntries: [StatusEntry] = [
        StatusEntry(id: "Sources/Grove/Views/WorkingCopy/WorkingCopyView.swift",
                    path: "Sources/Grove/Views/WorkingCopy/WorkingCopyView.swift",
                    indexStatus: .modified, workdirStatus: .unmodified),
        StatusEntry(id: "Sources/Grove/Views/History/HistoryView.swift",
                    path: "Sources/Grove/Views/History/HistoryView.swift",
                    indexStatus: .added, workdirStatus: .unmodified),
        StatusEntry(id: "Sources/Grove/Views/Sidebar/RepositorySidebar.swift",
                    path: "Sources/Grove/Views/Sidebar/RepositorySidebar.swift",
                    indexStatus: .unmodified, workdirStatus: .modified),
        StatusEntry(id: "Sources/Grove/Domain/AppState.swift",
                    path: "Sources/Grove/Domain/AppState.swift",
                    indexStatus: .unmodified, workdirStatus: .modified),
        StatusEntry(id: "Sources/Grove/Mocks/MockGitRepository.swift",
                    path: "Sources/Grove/Mocks/MockGitRepository.swift",
                    indexStatus: .modified, workdirStatus: .modified),
        StatusEntry(id: "Tests/GroveTests/CommitGraphTests.swift",
                    path: "Tests/GroveTests/CommitGraphTests.swift",
                    indexStatus: .added, workdirStatus: .unmodified),
        StatusEntry(id: "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
                    path: "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
                    indexStatus: .unmodified, workdirStatus: .modified),
        StatusEntry(id: "README.md",
                    path: "README.md",
                    indexStatus: .deleted, workdirStatus: .unmodified),
        StatusEntry(id: "docs/ARCHITECTURE.md",
                    path: "docs/ARCHITECTURE.md",
                    indexStatus: .unmodified, workdirStatus: .untracked),
        StatusEntry(id: "docs/CONVENTIONS.md",
                    path: "docs/CONVENTIONS.md",
                    indexStatus: .unmodified, workdirStatus: .untracked),
        StatusEntry(id: "Sources/Grove/Components/DiffViewer/DiffView.swift",
                    path: "Sources/Grove/Components/DiffViewer/DiffView.swift",
                    indexStatus: .added, workdirStatus: .modified),
        StatusEntry(id: "Sources/Grove/Views/Diff/DiffPanelView.swift",
                    path: "Sources/Grove/Views/Diff/DiffPanelView.swift",
                    indexStatus: .modified, workdirStatus: .unmodified),
        StatusEntry(id: "Package.resolved",
                    path: "Package.resolved",
                    indexStatus: .unmodified, workdirStatus: .modified),
        StatusEntry(id: "Sources/GitKit/Core/GitPointer.swift",
                    path: "Sources/GitKit/Core/GitPointer.swift",
                    indexStatus: .unmodified, workdirStatus: .untracked),
        StatusEntry(id: "Sources/GitKit/Repository/Repository.swift",
                    path: "Sources/GitKit/Repository/Repository.swift",
                    indexStatus: .unmodified, workdirStatus: .untracked),
        StatusEntry(id: "Sources/GitKit/Status/StatusList.swift",
                    path: "Sources/GitKit/Status/StatusList.swift",
                    indexStatus: .unmodified, workdirStatus: .untracked),
        StatusEntry(id: "CHANGELOG.md",
                    path: "CHANGELOG.md",
                    indexStatus: .renamed, workdirStatus: .unmodified),
        StatusEntry(id: "Sources/Grove/Views/Blame/BlameView.swift",
                    path: "Sources/Grove/Views/Blame/BlameView.swift",
                    indexStatus: .unmodified, workdirStatus: .deleted),
    ]

    // MARK: Diff

    static func diffResult(for path: String) -> DiffResult {
        DiffResult(
            filePath: path,
            oldPath: nil,
            isBinary: false,
            hunks: [hunk1, hunk2],
            stats: DiffStats(additions: 18, deletions: 7)
        )
    }

    private static let hunk1 = HunkData(
        id: "hunk-1",
        header: "@@ -10,12 +10,18 @@ final class WorkingCopyViewModel {",
        oldStart: 10, oldCount: 12,
        newStart: 10, newCount: 18,
        lines: [
            DiffLine(id: "h1-1", type: .context,  content: "    @Observable",           oldLineNumber: 10, newLineNumber: 10),
            DiffLine(id: "h1-2", type: .context,  content: "    final class WorkingCopyViewModel {", oldLineNumber: 11, newLineNumber: 11),
            DiffLine(id: "h1-3", type: .context,  content: "",                            oldLineNumber: 12, newLineNumber: 12),
            DiffLine(id: "h1-4", type: .deletion, content: "        var stagedFiles: [StatusEntry] = []", oldLineNumber: 13, newLineNumber: nil),
            DiffLine(id: "h1-5", type: .deletion, content: "        var unstagedFiles: [StatusEntry] = []", oldLineNumber: 14, newLineNumber: nil),
            DiffLine(id: "h1-6", type: .addition, content: "        var status: [StatusEntry] = []",      oldLineNumber: nil, newLineNumber: 13),
            DiffLine(id: "h1-7", type: .addition, content: "        var stagedFiles: [StatusEntry] {",    oldLineNumber: nil, newLineNumber: 14),
            DiffLine(id: "h1-8", type: .addition, content: "            status.filter { $0.indexStatus != .unmodified }", oldLineNumber: nil, newLineNumber: 15),
            DiffLine(id: "h1-9", type: .addition, content: "        }",                                  oldLineNumber: nil, newLineNumber: 16),
            DiffLine(id: "h1-10", type: .addition, content: "        var unstagedFiles: [StatusEntry] {", oldLineNumber: nil, newLineNumber: 17),
            DiffLine(id: "h1-11", type: .addition, content: "            status.filter { $0.workdirStatus != .unmodified }", oldLineNumber: nil, newLineNumber: 18),
            DiffLine(id: "h1-12", type: .addition, content: "        }",                                 oldLineNumber: nil, newLineNumber: 19),
            DiffLine(id: "h1-13", type: .context,  content: "",                           oldLineNumber: 15, newLineNumber: 20),
            DiffLine(id: "h1-14", type: .context,  content: "        let repository: any GitRepositoryProtocol", oldLineNumber: 16, newLineNumber: 21),
        ]
    )

    private static let hunk2 = HunkData(
        id: "hunk-2",
        header: "@@ -38,8 +44,10 @@ extension WorkingCopyViewModel {",
        oldStart: 38, oldCount: 8,
        newStart: 44, newCount: 10,
        lines: [
            DiffLine(id: "h2-1", type: .context,  content: "    func refresh() async {", oldLineNumber: 38, newLineNumber: 44),
            DiffLine(id: "h2-2", type: .context,  content: "        do {",               oldLineNumber: 39, newLineNumber: 45),
            DiffLine(id: "h2-3", type: .deletion, content: "            let s = try await repository.status()", oldLineNumber: 40, newLineNumber: nil),
            DiffLine(id: "h2-4", type: .deletion, content: "            stagedFiles = s.filter { ... }", oldLineNumber: 41, newLineNumber: nil),
            DiffLine(id: "h2-5", type: .addition, content: "            try await repository.refreshStatus()", oldLineNumber: nil, newLineNumber: 46),
            DiffLine(id: "h2-6", type: .addition, content: "            status = try await repository.status()", oldLineNumber: nil, newLineNumber: 47),
            DiffLine(id: "h2-7", type: .context,  content: "        } catch {",          oldLineNumber: 42, newLineNumber: 48),
            DiffLine(id: "h2-8", type: .deletion, content: "            print(error)",   oldLineNumber: 43, newLineNumber: nil),
            DiffLine(id: "h2-9", type: .addition, content: "            errorMessage = error.localizedDescription", oldLineNumber: nil, newLineNumber: 49),
            DiffLine(id: "h2-10", type: .context, content: "        }",                  oldLineNumber: 44, newLineNumber: 50),
            DiffLine(id: "h2-11", type: .context, content: "    }",                      oldLineNumber: 45, newLineNumber: 51),
        ]
    )

    static let commitFileDiffs: [FileDiff] = statusEntries.prefix(5).map { entry in
        FileDiff(
            path: entry.path,
            status: entry.indexStatus,
            diff: diffResult(for: entry.path),
            stats: DiffStats(additions: Int.random(in: 1...50), deletions: Int.random(in: 0...20))
        )
    }

    // MARK: Blame

    static let blameEntries: [BlameEntry] = {
        var entries: [BlameEntry] = []
        let shaPool = commits.map(\.id)
        let lineData: [(Int, Int, Int)] = [
            (1, 5, 0), (6, 8, 1), (14, 3, 2), (17, 10, 0),
            (27, 4, 1), (31, 12, 3), (43, 7, 0), (50, 6, 2),
        ]
        for (start, count, shaIdx) in lineData {
            let commit = commits[shaIdx]
            entries.append(BlameEntry(
                id: "\(commit.id)-\(start)",
                lineStart: start,
                lineCount: count,
                commitSHA: commit.id,
                authorName: commit.authorName,
                authorEmail: commit.authorEmail,
                authorDate: commit.authorDate,
                summary: commit.summary,
                originalPath: nil
            ))
        }
        return entries
    }()

    // MARK: Reflog

    static let reflogEntries: [ReflogEntry] = {
        var entries: [ReflogEntry] = []
        let messages = [
            "commit: feat: add OAuth2 authentication flow",
            "commit: refactor: split AuthManager into focused services",
            "pull: Fast-forward",
            "checkout: moving from develop to main",
            "merge feature/auth: Merge made by the 'ort' strategy.",
            "commit (amend): fix: prevent token refresh race condition",
            "rebase (finish): returning to refs/heads/main",
            "push origin main",
        ]
        let now = Date()
        for (i, msg) in messages.enumerated() {
            let commit = commits[min(i, commits.count - 1)]
            let prev   = commits[min(i + 1, commits.count - 1)]
            entries.append(ReflogEntry(
                id: "reflog-\(i)",
                oldSHA: prev.id,
                newSHA: commit.id,
                committerName: authorJane.name,
                committerEmail: authorJane.email,
                date: Calendar.current.date(byAdding: .hour, value: -i, to: now)!,
                message: msg
            ))
        }
        return entries
    }()
}
