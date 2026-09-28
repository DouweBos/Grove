// Views/WorkingCopy/WorkingCopyViewModel+Staging.swift
// Grove
//
// Staging files, singly or the whole selection, and the list order selection ranges follow.

import Foundation

extension WorkingCopyViewModel {

    func stageFile(_ entry: StatusEntry) async {
        await mutate {
            try await self.repository.stage(paths: [entry.path])
            self.undoManager?.record(GitUndoManager.stageAction(paths: [entry.path], repository: self.repository))
        }
    }

    func unstageFile(_ entry: StatusEntry) async {
        await mutate {
            try await self.repository.unstage(paths: [entry.path])
            self.undoManager?.record(GitUndoManager.unstageAction(paths: [entry.path], repository: self.repository))
        }
    }

    func stageAll() async {
        let paths = unstagedFiles.map(\.path)
        await mutate {
            try await self.repository.stageAll()
            self.undoManager?.record(GitUndoManager.stageAction(paths: paths, repository: self.repository))
        }
    }

    func unstageAll() async {
        let paths = stagedFiles.map(\.path)
        await mutate {
            try await self.repository.unstageAll()
            self.undoManager?.record(GitUndoManager.unstageAction(paths: paths, repository: self.repository))
        }
    }

    /// Space: selected changes are staged and selected staged files unstaged.
    func toggleStageOfSelection() async {
        let conflicted = Set(conflictedFiles.map(\.path))
        await toggleStage(fileSelection.rows.filter { !conflicted.contains($0.path) })
    }

    /// Stages the unstaged rows and unstages the staged ones, as one undo step.
    func toggleStage(_ rows: Set<FileRow>) async {
        let toStage = rows.filter { $0.side == .unstaged }.map(\.path).sorted()
        let toUnstage = rows.filter { $0.side == .staged }.map(\.path).sorted()
        guard !toStage.isEmpty || !toUnstage.isEmpty else { return }
        await mutate {
            var actions: [GitUndoManager.GitAction] = []
            if !toStage.isEmpty {
                try await self.repository.stage(paths: toStage)
                actions.append(GitUndoManager.stageAction(paths: toStage, repository: self.repository))
            }
            if !toUnstage.isEmpty {
                try await self.repository.unstage(paths: toUnstage)
                actions.append(GitUndoManager.unstageAction(paths: toUnstage, repository: self.repository))
            }
            self.undoManager?.record(actions.count == 1
                ? actions[0]
                : GitUndoManager.groupedAction(description: "Stage and Unstage \(rows.count) Files", actions: actions))
        }
    }

    // MARK: - Order

    /// Rows top to bottom as the list shows them, so Shift ranges and arrow keys follow the screen.
    var fileRowOrder: [FileRow] {
        var order = displayOrder(conflictedFiles).map { FileRow(path: $0.path, side: .unstaged) }
        guard !showOnlyConflicts else { return order }
        order += displayOrder(stagedFiles).map { FileRow(path: $0.path, side: .staged) }
        order += displayOrder(unstagedFiles).map { FileRow(path: $0.path, side: .unstaged) }
        return order
    }

    /// Entries grouped by directory in tree mode; flat mode keeps git's order.
    func directoryGroups(_ entries: [StatusEntry]) -> [(directory: String, entries: [StatusEntry])] {
        Dictionary(grouping: entries, by: \.directory)
            .sorted { $0.key < $1.key }
            .map { (directory: $0.key, entries: $0.value) }
    }

    private func displayOrder(_ entries: [StatusEntry]) -> [StatusEntry] {
        fileViewMode == .treeModified ? directoryGroups(entries).flatMap(\.entries) : entries
    }

    /// Where a selected row lives after the status changed: its side, else the file's other side, else gone.
    func placeRow(_ row: FileRow) -> FileRow? {
        guard let entry = statusEntries.first(where: { $0.path == row.path }) else { return nil }
        if entry.isConflicted { return FileRow(path: row.path, side: .unstaged) }
        let other: DiffSide = row.side == .staged ? .unstaged : .staged
        return [row.side, other].first { entry.has($0) }.map { FileRow(path: row.path, side: $0) }
    }
}

extension StatusEntry {
    func has(_ side: DiffSide) -> Bool {
        (side == .staged ? indexStatus : workdirStatus) != .unmodified
    }
}
