// ViewModels/WorkingCopyViewModel+FileActions.swift
// GroveKit
//
// Ignore, Stop Tracking, Rename and Delete for the files a Changes context menu acts on.

import Foundation

/// A rename or delete waiting for the user's input or confirmation.
public enum PendingFileAction: Identifiable {
    case rename(StatusEntry)
    case delete([StatusEntry])

    public var id: String {
        switch self {
        case .rename(let entry): "rename-\(entry.path)"
        case .delete(let entries): "delete-" + entries.map(\.path).joined(separator: "|")
        }
    }
}

/// What an Ignore menu item adds to the ignore file.
public enum IgnoreTarget: Hashable {
    case files
    case fileExtension(String)
    case folder(String)
}

extension WorkingCopyViewModel {

    /// Right-clicking inside the selection acts on every selected file; outside it, on the clicked one.
    public func actionEntries(for entry: StatusEntry, side: DiffSide) -> [StatusEntry] {
        let row = FileRow(path: entry.path, side: entry.isConflicted ? .unstaged : side)
        guard fileSelection.contains(row), fileSelection.count > 1 else { return [entry] }
        let paths = Set(fileSelection.rows.map(\.path))
        return statusEntries.filter { paths.contains($0.path) }
    }

    /// Extension and folder only when every file shares it, so one line covers them all.
    public func ignoreTargets(for entries: [StatusEntry]) -> [IgnoreTarget] {
        var targets: [IgnoreTarget] = [.files]
        let extensions = Set(entries.map { ($0.path as NSString).pathExtension })
        if extensions.count == 1, let ext = extensions.first, !ext.isEmpty { targets.append(.fileExtension(ext)) }
        let folders = Set(entries.map(\.directory))
        if folders.count == 1, let folder = folders.first, !folder.isEmpty { targets.append(.folder(folder)) }
        return targets
    }

    public func ignore(_ target: IgnoreTarget, of entries: [StatusEntry], localOnly: Bool) async {
        let patterns: [String]
        switch target {
        case .files: patterns = entries.map { GitIgnoreFile.pattern(forFile: $0.path) }
        case .fileExtension(let ext): patterns = [GitIgnoreFile.pattern(forExtension: ext)]
        case .folder(let folder): patterns = [GitIgnoreFile.pattern(forFolder: folder)]
        }
        await mutate { try await self.repository.ignore(patterns: patterns, localOnly: localOnly) }
    }

    /// Files git knows about; untracked ones have nothing to stop tracking.
    public func trackedEntries(_ entries: [StatusEntry]) -> [StatusEntry] {
        entries.filter { $0.workdirStatus != .untracked && $0.indexStatus != .deleted && !$0.isConflicted }
    }

    public func stopTracking(_ entries: [StatusEntry]) async {
        let paths = trackedEntries(entries).map(\.path)
        guard !paths.isEmpty else { return }
        let repo = repository
        await mutate {
            try await repo.stopTracking(paths: paths)
            undoManager?.record(GitUndoManager.GitAction(
                description: "Stop Tracking \(paths.count == 1 ? paths[0] : "\(paths.count) files")",
                undoCommand: { try await repo.unstage(paths: paths) },
                redoCommand: { try await repo.stopTracking(paths: paths) }))
        }
    }

    /// Files that still exist on disk, so they can be renamed or moved to the Trash.
    public func existingEntries(_ entries: [StatusEntry]) -> [StatusEntry] {
        entries.filter { $0.workdirStatus != .deleted && !($0.indexStatus == .deleted && $0.workdirStatus == .unmodified) }
    }

    public func requestRename(_ entry: StatusEntry) {
        pendingFileAction = .rename(entry)
    }

    public func requestDelete(_ entries: [StatusEntry]) {
        let existing = existingEntries(entries)
        guard !existing.isEmpty else { return }
        pendingFileAction = .delete(existing)
    }

    public func cancelFileAction() {
        pendingFileAction = nil
    }

    /// `newPath` is repository-relative, so a rename can also move the file into another folder.
    public func rename(_ entry: StatusEntry, to newPath: String) async {
        pendingFileAction = nil
        let destination = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty, destination != entry.path else { return }
        let (repo, source) = (repository, entry.path)
        await mutate {
            try await repo.moveFile(from: source, to: destination)
            undoManager?.record(GitUndoManager.GitAction(
                description: "Rename \((source as NSString).lastPathComponent)",
                undoCommand: { try await repo.moveFile(from: destination, to: source) },
                redoCommand: { try await repo.moveFile(from: source, to: destination) }))
        }
    }

    /// The Trash keeps the files recoverable, unlike Discard.
    public func moveToTrash(_ entries: [StatusEntry]) async {
        pendingFileAction = nil
        let repo = repository
        await mutate { try await repo.trashFiles(entries.map(\.path)) }
    }
}
