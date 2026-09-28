// Views/History/FileHistoryViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - FileHistoryViewModel

/// ViewModel for the File History view.
///
/// Loads the per-file commit history using `git log --follow -- <path>`
/// and the diff for the selected file at any given commit.
@Observable
@MainActor
final class FileHistoryViewModel {

    // MARK: - State

    /// All commits that touched ``filePath``, in reverse-chronological order.
    var commits: [CommitInfo] = []
    /// The commit currently selected in the list panel.
    var selectedCommit: CommitInfo?
    /// The file diff at the selected commit revision.
    var fileDiff: DiffResult?
    var isLoading = false
    var isLoadingDiff = false
    var errorMessage: String?
    /// A restore waiting for confirmation because the file has local changes it would overwrite.
    private(set) var pendingRestore: CommitInfo?
    /// The version last written into the working copy, for the inline confirmation.
    private(set) var restoredCommit: CommitInfo?
    private(set) var isRestoring = false

    /// Set by the presenter so a restore refreshes the Changes list and badges.
    var onRepositoryChanged: (() async -> Void)?

    // MARK: - Configuration

    private let maxCount = 500

    // MARK: - Dependencies

    /// The repository this history belongs to.
    let repository: any GitRepositoryProtocol
    /// Repository-relative path of the file whose history is shown.
    let filePath: String
    // Keyed by SHA; the path is fixed per view model, so this is effectively (sha, path).
    @ObservationIgnored private var diffCache = LRUCache<String, DiffResult>(capacity: 100)

    // MARK: - Init

    init(repository: any GitRepositoryProtocol, filePath: String) {
        self.repository = repository
        self.filePath = filePath
    }

    // MARK: - Actions

    /// Load the full file-level commit history.
    ///
    /// Uses `git log --follow -- <filePath>` via ``GitRepositoryProtocol/fileLog(path:maxCount:)``.
    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            commits = try await repository.fileLog(path: filePath, maxCount: maxCount)
            // Auto-select the first (most recent) commit.
            if let first = commits.first, selectedCommit == nil {
                await selectCommit(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Select a commit and load the file diff at that revision, from cache when revisited.
    func selectCommit(_ commit: CommitInfo) async {
        guard selectedCommit?.id != commit.id else { return }
        selectedCommit = commit
        if let cached = diffCache.value(for: commit.id) {
            fileDiff = cached
            isLoadingDiff = false
            return
        }
        fileDiff = nil
        isLoadingDiff = true
        do {
            let diff = try await loadFileDiff(at: commit)
            if let diff { diffCache.insert(diff, for: commit.id) }
            // A newer selection may have started while this diff was loading.
            guard selectedCommit?.id == commit.id else { return }
            fileDiff = diff
        } catch {
            errorMessage = error.localizedDescription
        }
        if selectedCommit?.id == commit.id { isLoadingDiff = false }
    }

    /// Diffs only this file; falls back to the whole commit when it had another name there,
    /// or when an addition is really the far side of a rename that `--follow` crossed.
    private func loadFileDiff(at commit: CommitInfo) async throws -> DiffResult? {
        let limited = try await repository.diffForCommit(commit.id, path: filePath)
        let isOldest = commit.id == commits.last?.id
        if let match = limited.first, match.status != .added || isOldest { return match.diff }
        let allDiffs = try await repository.diffForCommit(commit.id)
        let match = allDiffs.first { $0.path == filePath || $0.diff?.oldPath == filePath }
            ?? (allDiffs.count == 1 ? allDiffs.first : nil)
        return match?.diff ?? limited.first?.diff
    }

    // MARK: - Restore

    /// A commit that deleted the file has no version to restore.
    var canRestoreSelected: Bool {
        guard selectedCommit != nil, !isRestoring else { return false }
        guard let diff = fileDiff else { return true }
        let deletesFile = !diff.hunks.isEmpty && diff.hunks.allSatisfy { $0.newCount == 0 }
        return !deletesFile
    }

    /// Restores straight away on a clean file; local changes ask first since they'd be overwritten.
    func requestRestore(_ commit: CommitInfo) async {
        restoredCommit = nil
        let entries = (try? await repository.status()) ?? []
        let isDirty = entries.contains { $0.path == filePath && ($0.indexStatus != .unmodified || $0.workdirStatus != .unmodified) }
        if isDirty {
            pendingRestore = commit
        } else {
            await restore(commit)
        }
    }

    func cancelRestore() {
        pendingRestore = nil
    }

    func dismissRestoreNotice() {
        restoredCommit = nil
    }

    func restore(_ commit: CommitInfo) async {
        pendingRestore = nil
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }
        do {
            // Across a rename the file had another name at that commit.
            var diff = diffCache.value(for: commit.id)
            if diff == nil { diff = try await loadFileDiff(at: commit) }
            try await repository.restoreFile(filePath, from: commit.id, revisionPath: diff?.filePath ?? filePath)
            restoredCommit = commit
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
        await onRepositoryChanged?()
    }

    /// Export the file at the selected commit to a user-chosen disk location.
    ///
    /// Runs `git show <sha>:<path>` as a subprocess in the repository's working
    /// directory, then writes the result to `destinationURL`.
    ///
    /// - Parameter destinationURL: The URL returned by an `NSSavePanel`.
    func exportFile(to destinationURL: URL) async {
        guard let commit = selectedCommit else { return }
        errorMessage = nil
        do {
            let spec = "\(commit.id):\(filePath)"
            let gitURL = try await resolveGitExecutable()
            let content = try await runProcess(
                executable: gitURL,
                arguments: ["show", spec],
                workingDirectory: repository.path
            )
            try content.write(to: destinationURL, options: .atomic)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Helpers

    /// Resolve the `git` executable path, checking common macOS installation locations.
    nonisolated private func resolveGitExecutable() async throws -> URL {
        let candidates = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }

    /// Run a subprocess and return its standard-output as `Data`.
    nonisolated private func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let output = try await ProcessRunner.run(process)
        guard output.status == 0 else {
            let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
            throw NSError(
                domain: "FileHistoryViewModel",
                code: Int(output.status),
                userInfo: [NSLocalizedDescriptionKey: stderr.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
        return output.stdout
    }
}
