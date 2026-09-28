// Views/WorkingCopy/WorkingCopyViewModel.swift
// Grove
//
// State for the Working Copy ("Changes") tab: file status, selection, diff,
// commit composer and in-progress merge/rebase conflicts.

import Foundation
import Observation

/// How changed files are presented in the file list.
enum FileViewMode: String, CaseIterable {
    case flatModified = "List"
    case treeModified = "Tree"
    case allFiles = "All Files"

    var symbol: String {
        switch self {
        case .flatModified: "list.bullet"
        case .treeModified: "list.bullet.indent"
        case .allFiles: "folder"
        }
    }
}

/// Which half of a file's changes the diff panel shows.
enum DiffSide: Hashable {
    case staged
    case unstaged
}

@MainActor
@Observable
final class WorkingCopyViewModel {

    let repository: any GitRepositoryProtocol

    /// Set by the session so mutations refresh every view (sidebar badge, history), not just this one.
    var onRepositoryChanged: (() async -> Void)?
    var undoManager: GitUndoManager?

    // MARK: Status

    var statusEntries: [StatusEntry] = []
    var allTrackedFiles: [String] = []

    var conflictedFiles: [StatusEntry] { statusEntries.filter(\.isConflicted) }
    var stagedFiles: [StatusEntry] { statusEntries.filter { !$0.isConflicted && $0.indexStatus != .unmodified } }
    var unstagedFiles: [StatusEntry] { statusEntries.filter { !$0.isConflicted && $0.workdirStatus != .unmodified } }

    // MARK: Selection & Diff

    private(set) var selectedPath: String?
    private(set) var selectedSide: DiffSide = .unstaged

    var selectedEntry: StatusEntry? { statusEntries.first { $0.path == selectedPath } }
    var showingStaged: Bool { selectedSide == .staged }

    /// Only offer the Staged/Unstaged switch when the file has changes on both sides.
    var canSwitchDiffSide: Bool {
        guard let entry = selectedEntry, !entry.isConflicted else { return false }
        return entry.indexStatus != .unmodified && entry.workdirStatus != .unmodified
    }

    private(set) var currentDiff: DiffResult?
    private(set) var isDiffLoading = false
    /// Bumped on every diff load so views reading files directly (images) reload too.
    private(set) var diffLoadCount = 0
    private(set) var conflictVersions: ConflictVersions?

    private(set) var fileViewMode: FileViewMode = .flatModified
    private(set) var ignoreWhitespace = false
    private(set) var showOnlyConflicts = false

    // MARK: Commit Composer

    var commitSubject = "" {
        didSet { updateAutoComplete(text: commitSubject) }
    }
    var commitBody = ""
    private(set) var isAmend = false
    private(set) var signOff = false
    private(set) var signCommit = false
    private(set) var isSigningAvailable = false
    private(set) var identity: CommitIdentity?
    private(set) var isCommitting = false
    /// HEAD's message as loaded for amend, so turning amend off can drop an untouched prefill.
    private var amendPrefill: (subject: String, body: String)?

    var hasSubject: Bool { !commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canCommit: Bool { hasSubject && (isAmend || !stagedFiles.isEmpty) && conflictedFiles.isEmpty && !isCommitting }

    var commitButtonTitle: String {
        if isAmend { return "Amend Commit" }
        let count = stagedFiles.count
        return count == 0 ? "Commit" : "Commit \(count) \(count == 1 ? "File" : "Files")"
    }

    // MARK: Operations (merge / rebase / cherry-pick / revert)

    var repositoryState: RepositoryState { repository.repositoryState }
    var isInOperation: Bool {
        switch repositoryState {
        case .merge, .rebase, .rebaseInteractive, .cherrypick, .revert: true
        case .normal, .bisect: false
        }
    }
    private(set) var operationContext: OperationContext?
    private(set) var isRunningOperation = false

    // MARK: Autocomplete

    var autoCompleteTrigger: AutoCompleteTrigger?
    var autoCompleteSuggestions: [AutoCompleteSuggestion] = []
    var isAutoCompleteVisible: Bool { autoCompleteTrigger != nil && !autoCompleteSuggestions.isEmpty }
    /// Recent commits for the `c:` trigger, warmed on refresh.
    private(set) var cachedRecentCommits: [CommitInfo] = []

    // MARK: Misc

    private(set) var hasLoadedStatus = false
    private(set) var pendingDiscard: StatusEntry?
    private(set) var pendingHunkDiscard: PendingHunkDiscard?
    var errorMessage: String?

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Refresh

    func refresh() async {
        do {
            try await repository.refreshStatus()
            statusEntries = try await repository.status()
            hasLoadedStatus = true
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        allTrackedFiles = (try? await repository.listTrackedFiles()) ?? []
        cachedRecentCommits = (try? await repository.log(maxCount: 10, skip: 0, branch: nil)) ?? []
        isSigningAvailable = (try? await repository.isSigningConfigured()) ?? false
        identity = await repository.commitIdentity()
        operationContext = isInOperation ? await repository.operationContext() : nil
        if conflictedFiles.isEmpty { showOnlyConflicts = false }
        await reconcileSelection()
    }

    /// Keep the selection pointed at something that still has changes after the status moved.
    private func reconcileSelection() async {
        guard let entry = selectedEntry else {
            selectedPath = nil
            currentDiff = nil
            conflictVersions = nil
            return
        }
        if !entry.isConflicted {
            let hasSide = selectedSide == .staged ? entry.indexStatus != .unmodified : entry.workdirStatus != .unmodified
            if !hasSide { selectedSide = selectedSide == .staged ? .unstaged : .staged }
        }
        await loadDiff()
    }

    // MARK: - Selection

    /// Select a file; without an explicit side, show the working-tree changes when there are any.
    func select(_ entry: StatusEntry, side: DiffSide? = nil) async {
        selectedPath = entry.path
        selectedSide = side ?? (entry.workdirStatus != .unmodified ? .unstaged : .staged)
        await loadDiff()
    }

    func setDiffSide(_ side: DiffSide) async {
        guard side != selectedSide else { return }
        selectedSide = side
        await loadDiff()
    }

    func setIgnoreWhitespace(_ ignore: Bool) async {
        ignoreWhitespace = ignore
        await loadDiff()
    }

    func setFileViewMode(_ mode: FileViewMode) {
        fileViewMode = mode
    }

    func setShowOnlyConflicts(_ show: Bool) {
        showOnlyConflicts = show
    }

    func isSelected(_ entry: StatusEntry, side: DiffSide) -> Bool {
        selectedPath == entry.path && (entry.isConflicted || selectedSide == side)
    }

    private func loadDiff() async {
        guard let entry = selectedEntry else { return }
        diffLoadCount += 1
        isDiffLoading = true
        defer { isDiffLoading = false }
        if entry.isConflicted {
            currentDiff = nil
            conflictVersions = try? await repository.conflictVersions(path: entry.path)
            return
        }
        conflictVersions = nil
        do {
            currentDiff = try await repository.diff(for: entry, staged: showingStaged, ignoreWhitespace: ignoreWhitespace)
        } catch {
            currentDiff = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Staging

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

    func performHunkAction(_ action: HunkAction, hunk: HunkData, lines: [DiffLine] = []) async {
        guard let path = selectedEntry?.path else { return }
        if action.isDiscard && GrovePreferences.warnOnHunkDiscard {
            pendingHunkDiscard = PendingHunkDiscard(action: action, hunk: hunk, lines: lines, path: path)
            return
        }
        await applyHunkAction(action, hunk: hunk, lines: lines, path: path)
    }

    /// Takes the discard explicitly: the dialog clears `pendingHunkDiscard` before this task runs.
    func confirmHunkDiscard(_ pending: PendingHunkDiscard, dontAskAgain: Bool) async {
        pendingHunkDiscard = nil
        if dontAskAgain { GrovePreferences.warnOnHunkDiscard = false }
        await applyHunkAction(pending.action, hunk: pending.hunk, lines: pending.lines, path: pending.path)
    }

    func cancelHunkDiscard() {
        pendingHunkDiscard = nil
    }

    private func applyHunkAction(_ action: HunkAction, hunk: HunkData, lines: [DiffLine], path: String) async {
        let changed = lines.isEmpty ? hunk.lines.filter { $0.type != .context } : lines
        await mutate {
            let repo = self.repository
            switch action {
            case .stageHunk: try await repo.stageHunk(hunk, in: path)
            case .unstageHunk: try await repo.unstageHunk(hunk, in: path)
            case .discardHunk: try await repo.discardHunk(hunk, in: path)
            case .stageLines: try await repo.stageLines(changed, in: hunk, file: path)
            case .unstageLines: try await repo.unstageLines(changed, in: hunk, file: path)
            case .discardLines: try await repo.discardLines(changed, in: hunk, file: path)
            }
        }
    }

    // MARK: - Discard

    func requestDiscard(_ entry: StatusEntry) {
        pendingDiscard = entry
    }

    func cancelDiscard() {
        pendingDiscard = nil
    }

    /// Takes the entry explicitly: the dialog clears `pendingDiscard` before this task runs.
    func discard(_ entry: StatusEntry) async {
        pendingDiscard = nil
        await mutate { try await self.repository.discardChanges(paths: [entry.path]) }
    }

    // MARK: - Commit

    func setAmend(_ on: Bool) async {
        isAmend = on
        if on {
            guard !hasSubject, commitBody.isEmpty,
                  let head = try? await repository.commitDetail("HEAD") else { return }
            let body = head.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            commitSubject = head.summary
            commitBody = body
            amendPrefill = (head.summary, body)
            dismissAutoComplete()
        } else if let prefill = amendPrefill {
            if commitSubject == prefill.subject && commitBody == prefill.body {
                commitSubject = ""
                commitBody = ""
            }
            amendPrefill = nil
        }
    }

    func setSignOff(_ on: Bool) {
        signOff = on
    }

    func setSignCommit(_ on: Bool) {
        signCommit = on
    }

    func commit() async {
        guard canCommit else {
            if !hasSubject { errorMessage = "Please enter a commit subject." }
            return
        }
        isCommitting = true
        defer { isCommitting = false }
        do {
            let message = commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBody = commitBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmedBody.isEmpty ? nil : trimmedBody
            // No previous HEAD means the first commit, which a soft reset can't undo.
            let previousHead = try? await repository.commitDetail("HEAD").id
            let (repo, amend, sign, signOff) = (repository, isAmend, signCommit, signOff)
            let commit: @MainActor () async throws -> Void = {
                try await repo.commit(message: message, body: body, amend: amend, sign: sign, signOff: signOff)
            }
            try await commit()
            if let previousHead {
                undoManager?.record(GitUndoManager.commitAction(amend: amend, previousHead: previousHead,
                                                                repository: repo, recommit: commit))
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        commitSubject = ""
        commitBody = ""
        isAmend = false
        amendPrefill = nil
        dismissAutoComplete()
        await repositoryChanged()
    }

    // MARK: - Conflicts

    /// Jump to the first unresolved file so the diff panel shows the resolution UI.
    func resolveNextConflict() async {
        guard let first = conflictedFiles.first else { return }
        await select(first)
    }

    func resolveConflict(taking side: ConflictSide) async {
        guard let entry = selectedEntry, entry.isConflicted else { return }
        await mutate { try await self.repository.resolveConflict(path: entry.path, side: side) }
        if let next = conflictedFiles.first { await select(next) }
    }

    func abortOperation() async {
        await runOperation {
            let repo = self.repository
            switch self.repositoryState {
            case .rebase, .rebaseInteractive: try await repo.abortRebase()
            case .cherrypick: try await repo.abortCherryPick()
            case .revert: try await repo.abortRevert()
            default: try await repo.abortMerge()
            }
        }
    }

    func continueOperation() async {
        await runOperation { try await self.repository.continueOperation() }
    }

    private func runOperation(_ work: @escaping () async throws -> Void) async {
        isRunningOperation = true
        defer { isRunningOperation = false }
        await mutate(work)
    }

    // MARK: - Helpers

    func clearError() {
        errorMessage = nil
    }

    private func mutate(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        await repositoryChanged()
    }

    private func repositoryChanged() async {
        if let onRepositoryChanged {
            await onRepositoryChanged()
        } else {
            await refresh()
        }
    }
}

/// A hunk or line discard waiting for the user to confirm it.
struct PendingHunkDiscard {
    let action: HunkAction
    let hunk: HunkData
    let lines: [DiffLine]
    let path: String

    var title: String { action == .discardLines ? "Discard the selected lines?" : "Discard this hunk?" }
}

extension HunkAction {
    var isDiscard: Bool { self == .discardHunk || self == .discardLines }
}

extension StatusEntry {
    var isConflicted: Bool { indexStatus == .conflicted || workdirStatus == .conflicted }

    var fileName: String { (path as NSString).lastPathComponent }

    /// Parent directory with a trailing slash, or "" for root files.
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
}
