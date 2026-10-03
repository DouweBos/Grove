// ViewModels/FileHistoryViewModel.swift
// GroveKit

import Foundation
import Observation

// MARK: - FileHistoryViewModel

/// ViewModel for the File History view.
///
/// Loads the per-file commit history using `git log --follow -- <path>`
/// and the diff for the selected file at any given commit.
@Observable
@MainActor
public final class FileHistoryViewModel {

    // MARK: - State

    /// All commits that touched ``filePath``, in reverse-chronological order.
    public var commits: [CommitInfo] = []
    /// The commit currently selected in the list panel.
    public var selectedCommit: CommitInfo?
    /// The file diff at the selected commit revision.
    public var fileDiff: DiffResult?
    public var isLoading = false
    public var isLoadingDiff = false
    public var errorMessage: String?
    /// A restore waiting for confirmation because the file has local changes it would overwrite.
    public private(set) var pendingRestore: CommitInfo?
    /// The version last written into the working copy, for the inline confirmation.
    public private(set) var restoredCommit: CommitInfo?
    public private(set) var isRestoring = false

    /// Set by the presenter so a restore refreshes the Changes list and badges.
    public var onRepositoryChanged: (() async -> Void)?

    // MARK: - Configuration

    private let maxCount = 500

    // MARK: - Dependencies

    /// The repository this history belongs to.
    public let repository: any GitRepositoryProtocol
    /// Repository-relative path of the file whose history is shown.
    public let filePath: String
    // Keyed by SHA; the path is fixed per view model, so this is effectively (sha, path).
    @ObservationIgnored private var diffCache = LRUCache<String, DiffResult>(capacity: 100)

    // MARK: - Init

    public init(repository: any GitRepositoryProtocol, filePath: String) {
        self.repository = repository
        self.filePath = filePath
    }

    // MARK: - Actions

    /// Load the full file-level commit history.
    ///
    /// Uses `git log --follow -- <filePath>` via ``GitRepositoryProtocol/fileLog(path:maxCount:)``.
    public func loadHistory() async {
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
    public func selectCommit(_ commit: CommitInfo) async {
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
    public var canRestoreSelected: Bool {
        guard selectedCommit != nil, !isRestoring else { return false }
        guard let diff = fileDiff else { return true }
        let deletesFile = !diff.hunks.isEmpty && diff.hunks.allSatisfy { $0.newCount == 0 }
        return !deletesFile
    }

    /// Restores straight away on a clean file; local changes ask first since they'd be overwritten.
    public func requestRestore(_ commit: CommitInfo) async {
        restoredCommit = nil
        let entries = (try? await repository.status()) ?? []
        let isDirty = entries.contains { $0.path == filePath && ($0.indexStatus != .unmodified || $0.workdirStatus != .unmodified) }
        if isDirty {
            pendingRestore = commit
        } else {
            await restore(commit)
        }
    }

    public func cancelRestore() {
        pendingRestore = nil
    }

    public func dismissRestoreNotice() {
        restoredCommit = nil
    }

    public func restore(_ commit: CommitInfo) async {
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
    /// Reads the file through the repository, so LFS files export their content rather than the pointer.
    ///
    /// - Parameter destinationURL: Where the user chose to save it.
    public func exportFile(to destinationURL: URL) async {
        guard let commit = selectedCommit else { return }
        errorMessage = nil
        do {
            let content = try await repository.fileData(path: filePath, at: .commit(commit.id))
            try content.write(to: destinationURL, options: .atomic)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
