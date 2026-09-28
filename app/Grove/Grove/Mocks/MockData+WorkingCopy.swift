// Mocks/MockData+WorkingCopy.swift
// Grove
//
// Fake stashes, files, status, diffs and blame.

import Foundation

extension MockData {

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
        )
    ]

    // MARK: Tracked Files

    /// All paths returned by `git ls-files` — includes files from ``statusEntries``
    /// plus additional clean/unmodified tracked files that fill out a realistic
    /// project tree.
    static let trackedFiles: [String] = {
        // Start with the paths that have status changes.
        let changedPaths = statusEntries
            .filter { $0.workdirStatus != .untracked }
            .map(\.path)

        // Additional clean tracked files with no current changes.
        let cleanPaths: [String] = [
            ".gitignore",
            ".swiftlint.yml",
            "Package.swift",
            "Package.resolved",
            "LICENSE",
            "CHANGELOG.md",
            "README.md",
            "Sources/Grove/GroveApp.swift",
            "Sources/Grove/Domain/AppState.swift",
            "Sources/Grove/Domain/FileWatcher.swift",
            "Sources/Grove/Domain/RepositoryManager.swift",
            "Sources/Grove/Models/UserProfile.swift",
            "Sources/Grove/Protocols/GitRepositoryProtocol.swift",
            "Sources/Grove/Mocks/MockGitRepository.swift",
            "Sources/Grove/Views/WorkingCopy/WorkingCopyView.swift",
            "Sources/Grove/Views/WorkingCopy/WorkingCopyViewModel.swift",
            "Sources/Grove/Views/WorkingCopy/FileStatusListView.swift",
            "Sources/Grove/Views/WorkingCopy/FileStatusRow.swift",
            "Sources/Grove/Views/History/HistoryView.swift",
            "Sources/Grove/Views/History/CommitDetailView.swift",
            "Sources/Grove/Views/History/CommitListView.swift",
            "Sources/Grove/Views/Sidebar/RepositorySidebar.swift",
            "Sources/Grove/Views/Sidebar/BranchSectionView.swift",
            "Sources/Grove/Views/Sidebar/TagSectionView.swift",
            "Sources/Grove/Views/Diff/DiffPanelView.swift",
            "Sources/Grove/Views/Diff/HunkView.swift",
            "Sources/Grove/Views/Diff/DiffLineView.swift",
            "Sources/Grove/Views/Blame/BlameView.swift",
            "Sources/Grove/Views/Settings/SettingsView.swift",
            "Sources/Grove/Views/Settings/ProfileSettingsView.swift",
            "Sources/Grove/Components/DiffViewer/DiffView.swift",
            "Sources/Grove/Components/EmptyStateView.swift",
            "Sources/Grove/Components/StatusIcon.swift",
            "Sources/GitKit/Core/GitPointer.swift",
            "Sources/GitKit/Repository/Repository.swift",
            "Sources/GitKit/Status/StatusList.swift",
            "Sources/GitKit/Parsers/StatusParser.swift",
            "Sources/GitKit/Parsers/LogParser.swift",
            "Sources/GitKit/Parsers/DiffParser.swift",
            "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
            "Tests/GroveTests/CommitGraphTests.swift",
            "Tests/GroveTests/StatusParserTests.swift",
            "Tests/GroveTests/DiffParserTests.swift",
            "docs/ARCHITECTURE.md",
            "docs/CONVENTIONS.md"
        ]

        // Merge, deduplicate, and sort alphabetically to mirror `git ls-files` output.
        let all = Set(changedPaths + cleanPaths)
        return all.sorted()
    }()

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
                    indexStatus: .unmodified, workdirStatus: .deleted)
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
            DiffLine(id: "h1-1", type: .context, content: "    @Observable", oldLineNumber: 10, newLineNumber: 10),
            DiffLine(id: "h1-2", type: .context, content: "    final class WorkingCopyViewModel {", oldLineNumber: 11, newLineNumber: 11),
            DiffLine(id: "h1-3", type: .context, content: "", oldLineNumber: 12, newLineNumber: 12),
            DiffLine(id: "h1-4", type: .deletion, content: "        var stagedFiles: [StatusEntry] = []", oldLineNumber: 13, newLineNumber: nil),
            DiffLine(id: "h1-5", type: .deletion, content: "        var unstagedFiles: [StatusEntry] = []", oldLineNumber: 14, newLineNumber: nil),
            DiffLine(id: "h1-6", type: .addition, content: "        var status: [StatusEntry] = []", oldLineNumber: nil, newLineNumber: 13),
            DiffLine(id: "h1-7", type: .addition, content: "        var stagedFiles: [StatusEntry] {", oldLineNumber: nil, newLineNumber: 14),
            DiffLine(id: "h1-8", type: .addition, content: "            status.filter { $0.indexStatus != .unmodified }", oldLineNumber: nil, newLineNumber: 15),
            DiffLine(id: "h1-9", type: .addition, content: "        }", oldLineNumber: nil, newLineNumber: 16),
            DiffLine(id: "h1-10", type: .addition, content: "        var unstagedFiles: [StatusEntry] {", oldLineNumber: nil, newLineNumber: 17),
            DiffLine(id: "h1-11", type: .addition, content: "            status.filter { $0.workdirStatus != .unmodified }", oldLineNumber: nil, newLineNumber: 18),
            DiffLine(id: "h1-12", type: .addition, content: "        }", oldLineNumber: nil, newLineNumber: 19),
            DiffLine(id: "h1-13", type: .context, content: "", oldLineNumber: 15, newLineNumber: 20),
            DiffLine(id: "h1-14", type: .context, content: "        let repository: any GitRepositoryProtocol", oldLineNumber: 16, newLineNumber: 21)
        ]
    )

    private static let hunk2 = HunkData(
        id: "hunk-2",
        header: "@@ -38,8 +44,10 @@ extension WorkingCopyViewModel {",
        oldStart: 38, oldCount: 8,
        newStart: 44, newCount: 10,
        lines: [
            DiffLine(id: "h2-1", type: .context, content: "    func refresh() async {", oldLineNumber: 38, newLineNumber: 44),
            DiffLine(id: "h2-2", type: .context, content: "        do {", oldLineNumber: 39, newLineNumber: 45),
            DiffLine(id: "h2-3", type: .deletion, content: "            let s = try await repository.status()", oldLineNumber: 40, newLineNumber: nil),
            DiffLine(id: "h2-4", type: .deletion, content: "            stagedFiles = s.filter { ... }", oldLineNumber: 41, newLineNumber: nil),
            DiffLine(id: "h2-5", type: .addition, content: "            try await repository.refreshStatus()", oldLineNumber: nil, newLineNumber: 46),
            DiffLine(id: "h2-6", type: .addition, content: "            status = try await repository.status()", oldLineNumber: nil, newLineNumber: 47),
            DiffLine(id: "h2-7", type: .context, content: "        } catch {", oldLineNumber: 42, newLineNumber: 48),
            DiffLine(id: "h2-8", type: .deletion, content: "            print(error)", oldLineNumber: 43, newLineNumber: nil),
            DiffLine(id: "h2-9", type: .addition, content: "            errorMessage = error.localizedDescription", oldLineNumber: nil, newLineNumber: 49),
            DiffLine(id: "h2-10", type: .context, content: "        }", oldLineNumber: 44, newLineNumber: 50),
            DiffLine(id: "h2-11", type: .context, content: "    }", oldLineNumber: 45, newLineNumber: 51)
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
            (27, 4, 1), (31, 12, 3), (43, 7, 0), (50, 6, 2)
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
}
