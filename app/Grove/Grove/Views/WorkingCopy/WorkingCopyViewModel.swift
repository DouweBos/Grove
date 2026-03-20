// Views/WorkingCopy/WorkingCopyViewModel.swift
// Grove
//
// Observable ViewModel for the Working Copy feature area.
// Drives CommitComposerView, FileStatusListView, and DiffPanelView.
// Depends only on GitRepositoryProtocol — no concrete Git types imported.

import Foundation
import Observation

// MARK: - WorkingCopyViewModel

/// Central state manager for the Working Copy three-zone layout.
///
/// Inject into the view hierarchy via `.environment`:
/// ```swift
/// WorkingCopyView()
///     .environment(WorkingCopyViewModel(repository: MockGitRepository()))
/// ```
@Observable
final class WorkingCopyViewModel {

    // MARK: Injected

    let repository: any GitRepositoryProtocol

    // MARK: Status State

    /// All status entries for the current working tree.
    var statusEntries: [StatusEntry] = []

    /// Files with staged changes (index status ≠ unmodified).
    var stagedFiles: [StatusEntry] {
        statusEntries.filter { $0.indexStatus != .unmodified }
    }

    /// Files with unstaged changes (workdir status ≠ unmodified).
    var unstagedFiles: [StatusEntry] {
        statusEntries.filter { $0.workdirStatus != .unmodified }
    }

    // MARK: Selection State

    /// Currently selected status entry — drives the diff panel.
    var selectedEntry: StatusEntry?

    // MARK: Diff State

    /// Whether the diff panel shows staged (true) or unstaged (false) diff.
    var showingStaged: Bool = true

    /// The diff currently displayed in the right panel.
    var currentDiff: DiffResult?
    var isDiffLoading: Bool = false

    // MARK: Commit Composer State

    var commitSubject: String = ""
    var commitBody: String = ""
    var isAmend: Bool = false
    var signOff: Bool = false

    // MARK: Loading / Error State

    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: Public API — Status

    /// Refresh status from the repository.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.refreshStatus()
            statusEntries = try await repository.status()
            // Re-load diff if the selected entry is still present.
            if let selected = selectedEntry,
               statusEntries.contains(where: { $0.id == selected.id }) {
                await loadDiff(for: selected)
            } else {
                selectedEntry = nil
                currentDiff = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Public API — Selection

    /// Select a file and load its diff.
    func select(_ entry: StatusEntry) async {
        selectedEntry = entry
        await loadDiff(for: entry)
    }

    /// Toggle between staged and unstaged diff view.
    func toggleStagedUnstaged() async {
        showingStaged.toggle()
        if let entry = selectedEntry {
            await loadDiff(for: entry)
        }
    }

    // MARK: Public API — Staging

    func stageFile(_ entry: StatusEntry) async {
        do {
            try await repository.stage(paths: [entry.path])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unstageFile(_ entry: StatusEntry) async {
        do {
            try await repository.unstage(paths: [entry.path])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stageAll() async {
        do {
            try await repository.stageAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unstageAll() async {
        do {
            try await repository.unstageAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performHunkAction(_ action: HunkAction, hunk: HunkData, in entry: StatusEntry) async {
        do {
            switch action {
            case .stageHunk:
                try await repository.stageHunk(hunk, in: entry.path)
            case .unstageHunk:
                try await repository.unstageHunk(hunk, in: entry.path)
            case .discardHunk:
                try await repository.discardHunk(hunk, in: entry.path)
            case .stageLines:
                let lines = hunk.lines.filter { $0.type != .context }
                try await repository.stageLines(lines, in: hunk, file: entry.path)
            case .unstageLines:
                let lines = hunk.lines.filter { $0.type != .context }
                try await repository.unstageLines(lines, in: hunk, file: entry.path)
            case .discardLines:
                // Discard lines: unstage them from the index.
                let lines = hunk.lines.filter { $0.type != .context }
                try await repository.unstageLines(lines, in: hunk, file: entry.path)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discardFile(_ entry: StatusEntry) async {
        do {
            try await repository.discardChanges(paths: [entry.path])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Public API — Commit

    /// Create a commit from the current staged changes.
    func commit() async {
        guard !commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a commit subject."
            return
        }
        do {
            let body = commitBody.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await repository.commit(
                message: commitSubject,
                body: body.isEmpty ? nil : body,
                amend: isAmend
            )
            commitSubject = ""
            commitBody = ""
            isAmend = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Private

    private func loadDiff(for entry: StatusEntry) async {
        isDiffLoading = true
        defer { isDiffLoading = false }
        do {
            currentDiff = try await repository.diff(for: entry, staged: showingStaged)
        } catch {
            currentDiff = nil
            errorMessage = error.localizedDescription
        }
    }
}
