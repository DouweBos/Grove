// ViewModels/WorkingCopyViewModel.swift
// GroveKit
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
    /// Only read while the All Files mode is shown; `ls-files` is slow on large repositories.
    private(set) var allTrackedFiles: [String] = []
    private var trackedFilesAreStale = true

    var conflictedFiles: [StatusEntry] { statusEntries.filter(\.isConflicted) }
    /// Staged or unstaged entries, for the Changes badge.
    var changedCount: Int { statusEntries.filter { $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified }.count }
    var stagedFiles: [StatusEntry] { statusEntries.filter { !$0.isConflicted && $0.indexStatus != .unmodified } }
    var unstagedFiles: [StatusEntry] { statusEntries.filter { !$0.isConflicted && $0.workdirStatus != .unmodified } }

    // MARK: Selection & Diff

    private(set) var selectedPath: String?
    private(set) var selectedSide: DiffSide = .unstaged
    /// Rows Space and the context menu act on; the diff shows its focus.
    private(set) var fileSelection = FileSelection()

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
    @ObservationIgnored private var diffCache = WorkingDiffCache()

    private(set) var fileViewMode: FileViewMode = .flatModified
    private(set) var ignoreWhitespace = false
    private(set) var showOnlyConflicts = false

    // MARK: Commit Composer

    var commitSubject = "" {
        didSet { updateAutoComplete(text: commitSubject) }
    }
    var commitBody = ""
    var isAmend = false
    var signOff = false
    var signCommit = false
    private(set) var isSigningAvailable = false
    private(set) var identity: CommitIdentity?
    var isCommitting = false
    /// HEAD's message as loaded for amend, so turning amend off can drop an untouched prefill.
    var amendPrefill: (subject: String, body: String)?
    let templateStore: CommitTemplateStore
    /// The repository's `commit.template`, offered first and prefilled into an empty composer once per commit.
    var gitTemplate: CommitTemplate?
    var didPrefillGitTemplate = false

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
    /// The stack restack this operation belongs to, whose Continue and Abort cover the whole cascade.
    private(set) var pendingRestack: RestackPlan?
    var isRunningOperation = false

    // MARK: Autocomplete

    var autoCompleteTrigger: AutoCompleteTrigger?
    var autoCompleteSuggestions: [AutoCompleteSuggestion] = []
    /// The suggestion Return picks; the subject field keeps focus, so arrow keys move this.
    var autoCompleteHighlight: String?
    var isAutoCompleteVisible: Bool { autoCompleteTrigger != nil && !autoCompleteSuggestions.isEmpty }
    /// Recent commits for the `c:` trigger, warmed on refresh.
    private(set) var cachedRecentCommits: [CommitInfo] = []

    // MARK: Misc

    private(set) var hasLoadedStatus = false
    private(set) var lfs = WorkingCopyLFS()
    private(set) var pendingDiscard: [StatusEntry]?
    private(set) var pendingHunkDiscard: PendingHunkDiscard?
    var pendingFileAction: PendingFileAction?
    var patchApply: PatchApplyRequest?
    var isChoosingPatch = false
    var errorMessage: String?

    /// Without a `templateStore`, templates are kept in memory only.
    init(repository: any GitRepositoryProtocol, templateStore: CommitTemplateStore? = nil) {
        self.repository = repository
        self.templateStore = templateStore ?? CommitTemplateStore()
    }

    // MARK: - Refresh

    func refresh() async {
        do {
            try await repository.refreshStatus()
            statusEntries = try await repository.status()
            diffCache.statusRefreshed(statusEntries)
            hasLoadedStatus = true
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        trackedFilesAreStale = true
        async let trackedFiles: Void = loadTrackedFilesIfShown()
        async let recent = try? repository.log(maxCount: 10, skip: 0, branch: nil)
        async let signing = try? repository.isSigningConfigured()
        async let commitIdentity = repository.commitIdentity()
        async let context = isInOperation ? repository.operationContext() : nil
        async let lfsState = WorkingCopyLFS.load(repository, paths: statusEntries.map(\.path))
        async let template = repository.commitTemplate()
        async let restack = isInOperation ? repository.pendingRestack() : nil
        cachedRecentCommits = await recent ?? []
        lfs = await lfsState
        setGitTemplate(await template)
        isSigningAvailable = await signing ?? false
        identity = await commitIdentity
        operationContext = await context
        pendingRestack = await restack
        await trackedFiles
        if conflictedFiles.isEmpty { showOnlyConflicts = false }
        await reconcileSelection()
    }

    private func loadTrackedFilesIfShown() async {
        guard fileViewMode == .allFiles, trackedFilesAreStale else { return }
        trackedFilesAreStale = false
        allTrackedFiles = (try? await repository.listTrackedFiles()) ?? []
    }

    /// Keep the selection pointed at something that still has changes after the status moved.
    private func reconcileSelection() async {
        fileSelection.reconcile(placeRow)
        if let focus = fileSelection.focus {
            selectedPath = focus.path
            selectedSide = focus.side
        }
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
        fileSelection.select(FileRow(path: entry.path, side: entry.isConflicted ? .unstaged : selectedSide))
        await loadDiff()
    }

    /// A click in the Changes list; Shift extends the range and Cmd toggles, as in Finder.
    func click(_ entry: StatusEntry, side: DiffSide, extend: Bool, toggle: Bool) async {
        fileSelection.click(FileRow(path: entry.path, side: side), in: fileRowOrder, extend: extend, toggle: toggle)
        await showSelectionFocus()
    }

    func moveSelection(by offset: Int, extend: Bool) async {
        fileSelection.move(by: offset, in: fileRowOrder, extend: extend)
        await showSelectionFocus()
    }

    private func showSelectionFocus() async {
        guard let focus = fileSelection.focus, focus.path != selectedPath || focus.side != selectedSide else { return }
        selectedPath = focus.path
        selectedSide = focus.side
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

    func setFileViewMode(_ mode: FileViewMode) async {
        fileViewMode = mode
        await loadTrackedFilesIfShown()
    }

    func setShowOnlyConflicts(_ show: Bool) {
        showOnlyConflicts = show
    }

    func isSelected(_ entry: StatusEntry, side: DiffSide) -> Bool {
        fileSelection.contains(FileRow(path: entry.path, side: entry.isConflicted ? .unstaged : side))
    }

    private func loadDiff() async {
        guard let entry = selectedEntry else { return }
        diffLoadCount += 1
        if entry.isConflicted {
            currentDiff = nil
            isDiffLoading = true
            defer { isDiffLoading = false }
            conflictVersions = try? await repository.conflictVersions(path: entry.path)
            return
        }
        conflictVersions = nil
        let key = WorkingDiffCache.Key(path: entry.path, side: selectedSide, ignoreWhitespace: ignoreWhitespace)
        // Another file's diff must never sit under this file's name, so a miss starts empty.
        let hit = diffCache.lookup(key)
        currentDiff = hit?.diff
        guard hit?.isCurrent != true else {
            isDiffLoading = false
            return
        }
        let generation = diffCache.generation
        isDiffLoading = true
        defer { if isShowing(key) { isDiffLoading = false } }
        do {
            let diff = try await repository.diff(for: entry, staged: key.side == .staged, ignoreWhitespace: key.ignoreWhitespace)
            diffCache.store(diff, for: key, status: entry, loadedAt: generation)
            if isShowing(key) { currentDiff = diff }
        } catch {
            guard isShowing(key) else { return }
            currentDiff = nil
            errorMessage = error.localizedDescription
        }
    }

    private func isShowing(_ key: WorkingDiffCache.Key) -> Bool {
        selectedPath == key.path && selectedSide == key.side && ignoreWhitespace == key.ignoreWhitespace
    }

    func performHunkAction(_ action: HunkAction, hunk: HunkData, lines: [DiffLine] = []) async {
        guard let path = selectedEntry?.path else { return }
        if action.isDiscard && ViewModelPreferences.warnOnHunkDiscard {
            pendingHunkDiscard = PendingHunkDiscard(action: action, hunk: hunk, lines: lines, path: path)
            return
        }
        await applyHunkAction(action, hunk: hunk, lines: lines, path: path)
    }

    /// Takes the discard explicitly: the dialog clears `pendingHunkDiscard` before this task runs.
    func confirmHunkDiscard(_ pending: PendingHunkDiscard, dontAskAgain: Bool) async {
        pendingHunkDiscard = nil
        if dontAskAgain { ViewModelPreferences.warnOnHunkDiscard = false }
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

    func requestDiscard(_ entries: [StatusEntry]) {
        pendingDiscard = entries.isEmpty ? nil : entries
    }

    func cancelDiscard() {
        pendingDiscard = nil
    }

    /// Takes the entries explicitly: the dialog clears `pendingDiscard` before this task runs.
    func discard(_ entries: [StatusEntry]) async {
        pendingDiscard = nil
        await mutate { try await self.repository.discardChanges(paths: entries.map(\.path)) }
    }

    // MARK: - Helpers

    func clearError() {
        errorMessage = nil
    }

    func mutate(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        await repositoryChanged()
    }

    func repositoryChanged() async {
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
