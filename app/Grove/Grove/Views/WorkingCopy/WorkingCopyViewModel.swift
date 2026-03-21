// Views/WorkingCopy/WorkingCopyViewModel.swift
// Grove
//
// Observable ViewModel for the Working Copy feature area.
// Drives CommitComposerView, FileStatusListView, and DiffPanelView.
// Depends only on GitRepositoryProtocol — no concrete Git types imported.

import Foundation
import Observation

// MARK: - FileViewMode

/// Controls how the file list is presented in the Working Copy left column.
enum FileViewMode: String, CaseIterable {
    /// Flat list of all files with changes (default).
    case flatModified = "Modified"
    /// Changed files grouped into a collapsible directory tree.
    case treeModified = "Tree"
    /// Complete repository file tree (placeholder — coming soon).
    case allFiles = "All"
}

// MARK: - UserProfileData

/// A lightweight value type that bridges ``UserProfile`` (SwiftData) to the view layer.
///
/// Views and ViewModels always work with this struct, never with the raw
/// SwiftData model.
struct UserProfileData: Identifiable, Hashable, Sendable {
    /// Mirrors ``UserProfile/profileID``.
    let id: UUID
    /// Committer name as it will appear in git commits.
    let name: String
    /// Committer email as it will appear in git commits.
    let email: String
    /// GPG or SSH signing key fingerprint, if commit signing is enabled.
    let signingKeyID: String?
    /// Whether this is the default/pre-selected profile.
    let isDefault: Bool

    /// The first character of `name`, used for avatar initials.
    var initial: String { String(name.prefix(1).uppercased()) }
}

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

    /// All tracked file paths, populated by `git ls-files`. Used by the
    /// ``FileViewMode/allFiles`` tree view to show every file in the repository.
    var allTrackedFiles: [String] = []

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

    // MARK: File View Mode

    /// Controls how changed files are presented in the file list.
    var fileViewMode: FileViewMode = .flatModified

    // MARK: Diff Options

    /// When `true`, whitespace-only changes are hidden in the diff panel.
    var ignoreWhitespace: Bool = false

    // MARK: Conflict Filter

    /// When `true`, the file list is filtered to show only conflicted files.
    /// Set by ``ConflictBannerView`` during a merge/rebase conflict state.
    var showOnlyConflicts: Bool = false

    // MARK: Commit Composer State

    var commitSubject: String = "" {
        didSet { updateAutoComplete(text: commitSubject) }
    }
    var commitBody: String = ""
    var isAmend: Bool = false
    var signOff: Bool = false

    // MARK: Signing State

    /// Whether the next commit should be signed with the configured GPG/SSH key.
    var signCommit: Bool = false

    /// Whether GPG/SSH signing is configured in the repository's effective git config.
    ///
    /// Populated during ``refresh()``. The "Sign" toggle in ``CommitComposerView``
    /// is only visible when this is `true`.
    var isSigningAvailable: Bool = false

    // MARK: Autocomplete State

    /// The active trigger, or `nil` when the dropdown is hidden.
    var autoCompleteTrigger: AutoCompleteTrigger?

    /// Suggestions to display in the autocomplete dropdown.
    var autoCompleteSuggestions: [AutoCompleteSuggestion] = []

    /// Whether the autocomplete dropdown is currently visible.
    var isAutoCompleteVisible: Bool { autoCompleteTrigger != nil && !autoCompleteSuggestions.isEmpty }

    // MARK: User Profile State

    /// All profiles available for selection in the commit composer.
    ///
    /// Populated via ``loadProfiles(from:)``. During development/preview
    /// this is populated by ``loadDefaultPreviewProfiles()``.
    var availableProfiles: [UserProfileData] = []

    /// The profile whose identity will be used for the next commit.
    var selectedProfile: UserProfileData?

    // MARK: Loading / Error State

    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: Private cache

    /// Recently fetched commits cached for the `c:` autocomplete trigger.
    private var cachedRecentCommits: [CommitInfo] = []

    // MARK: Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
        loadDefaultPreviewProfiles()
    }

    // MARK: Public API — Status

    /// Refresh status from the repository.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.refreshStatus()
            statusEntries = try await repository.status()
            // Load tracked files for the All Files tree view.
            allTrackedFiles = (try? await repository.listTrackedFiles()) ?? []
            // Warm the commit cache for autocomplete.
            cachedRecentCommits = (try? await repository.log(maxCount: 10, skip: 0, branch: nil)) ?? []
            // Detect whether GPG/SSH signing is configured.
            isSigningAvailable = (try? await repository.isSigningConfigured()) ?? false
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
                amend: isAmend,
                sign: signCommit
            )
            commitSubject = ""
            commitBody = ""
            isAmend = false
            signCommit = false
            dismissAutoComplete()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Public API — Autocomplete

    /// Examine `text` for a trigger prefix and refresh ``autoCompleteSuggestions``.
    ///
    /// Call this whenever `commitSubject` changes. The method is synchronous
    /// so it executes on the main actor alongside the `@Observable` property
    /// mutations; expensive lookups (e.g. `c:`) use the pre-warmed cache.
    func updateAutoComplete(text: String) {
        guard let (trigger, query) = detectTrigger(in: text) else {
            autoCompleteTrigger = nil
            autoCompleteSuggestions = []
            return
        }

        autoCompleteTrigger = trigger
        autoCompleteSuggestions = generateSuggestions(trigger: trigger, query: query)
    }

    /// Apply a chosen suggestion: replace the trigger + query with `insertText`.
    func applyAutoComplete(_ suggestion: AutoCompleteSuggestion) {
        guard let trigger = autoCompleteTrigger else { return }
        let triggerPrefix = prefix(for: trigger)
        // Find the last occurrence of the trigger prefix and replace from there.
        if let range = commitSubject.range(of: triggerPrefix, options: .backwards) {
            commitSubject = commitSubject.replacingCharacters(in: range, with: suggestion.insertText)
        }
        dismissAutoComplete()
    }

    /// Hide the autocomplete dropdown without modifying the subject text.
    func dismissAutoComplete() {
        autoCompleteTrigger = nil
        autoCompleteSuggestions = []
    }

    // MARK: Public API — Profiles

    /// Populate ``availableProfiles`` from an external source (e.g. a SwiftData query result).
    ///
    /// The first profile with `isDefault == true` is pre-selected, falling back
    /// to the first profile in the list.
    func loadProfiles(from profiles: [UserProfileData]) {
        availableProfiles = profiles
        if selectedProfile == nil || !profiles.contains(where: { $0.id == selectedProfile?.id }) {
            selectedProfile = profiles.first(where: \.isDefault) ?? profiles.first
        }
    }

    // MARK: Private — Autocomplete Detection

    /// Returns the matched ``AutoCompleteTrigger`` and the query text that follows it,
    /// or `nil` if the current text does not end with a recognised trigger sequence.
    private func detectTrigger(in text: String) -> (AutoCompleteTrigger, String)? {
        // `c:` must be checked before single-char triggers to avoid a false match on `c`.
        if let range = text.range(of: "c:", options: .backwards) {
            let query = String(text[range.upperBound...])
            return (.commit, query)
        }
        for (char, trigger) in [("#", AutoCompleteTrigger.issue),
                                 ("`", .filename),
                                 ("/", .template)] {
            if let range = text.range(of: char, options: .backwards) {
                // Only treat as active when the trigger is at the end of the text
                // (nothing after it except the query).
                let query = String(text[range.upperBound...])
                // Abort if the query contains whitespace — the user has moved on.
                guard !query.contains(" ") else { continue }
                return (trigger, query)
            }
        }
        return nil
    }

    /// Returns the trigger prefix string used when replacing text on selection.
    private func prefix(for trigger: AutoCompleteTrigger) -> String {
        switch trigger {
        case .issue:    return "#"
        case .commit:   return "c:"
        case .filename: return "`"
        case .template: return "/"
        }
    }

    // MARK: Private — Suggestion Generation

    private func generateSuggestions(trigger: AutoCompleteTrigger, query: String) -> [AutoCompleteSuggestion] {
        let query = query.lowercased()
        switch trigger {
        case .issue:
            return issueSuggestions(query: query)
        case .commit:
            return commitSuggestions(query: query)
        case .filename:
            return filenameSuggestions(query: query)
        case .template:
            return templateSuggestions(query: query)
        }
    }

    // MARK: Private — Issue Suggestions

    /// Extract issue / PR identifiers from known branch names.
    ///
    /// Recognised patterns:
    /// - `PROJ-123`  — Jira-style alphanumeric project key + number
    /// - `#42`       — GitHub-style numeric prefix in branch names (e.g. `feature/42-dark-mode`)
    ///
    /// Uses the current branch name synchronously. A richer implementation
    /// could call `localBranches()` asynchronously and cache the results.
    private func issueSuggestions(query: String) -> [AutoCompleteSuggestion] {
        var found: [String] = []

        // Scan the current branch name.
        if let name = repository.currentBranch?.name {
            found += extractIssueIDs(from: name)
        }

        // Deduplicate while preserving insertion order.
        var seen = Set<String>()
        let unique = found.filter { seen.insert($0).inserted }

        let filtered = query.isEmpty ? unique : unique.filter { $0.lowercased().contains(query) }

        return filtered.map { issueID in
            AutoCompleteSuggestion(
                id: issueID,
                icon: "number",
                title: issueID,
                subtitle: repository.currentBranch?.name,
                insertText: issueID
            )
        }
    }

    /// Returns all issue-like tokens found in `text`.
    private func extractIssueIDs(from text: String) -> [String] {
        var results: [String] = []
        // Jira-style: PROJ-123
        let jiraPattern = try? NSRegularExpression(pattern: "[A-Z][A-Z0-9]+-\\d+")
        let nsText = text as NSString
        let jiraMatches = jiraPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []
        results += jiraMatches.map { nsText.substring(with: $0.range) }

        // GitHub-style issue number embedded in branch: feature/42-dark-mode → #42
        let ghPattern = try? NSRegularExpression(pattern: "(?:^|[/_-])(\\d{1,6})(?:[/_-]|$)")
        let ghMatches = ghPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []
        for match in ghMatches where match.numberOfRanges > 1 {
            let num = nsText.substring(with: match.range(at: 1))
            results.append("#\(num)")
        }

        return results
    }

    // MARK: Private — Commit Suggestions

    private func commitSuggestions(query: String) -> [AutoCompleteSuggestion] {
        let candidates = cachedRecentCommits
        let filtered = query.isEmpty
            ? candidates
            : candidates.filter {
                $0.summary.lowercased().contains(query) ||
                $0.shortSHA.lowercased().hasPrefix(query)
            }

        return filtered.prefix(8).map { commit in
            AutoCompleteSuggestion(
                id: commit.id,
                icon: "arrow.triangle.branch",
                title: commit.summary,
                subtitle: commit.shortSHA,
                insertText: commit.shortSHA
            )
        }
    }

    // MARK: Private — Filename Suggestions

    private func filenameSuggestions(query: String) -> [AutoCompleteSuggestion] {
        let entries = statusEntries
        let filtered = query.isEmpty
            ? entries
            : entries.filter { $0.path.lowercased().contains(query) }

        return filtered.prefix(10).map { entry in
            let url = URL(fileURLWithPath: entry.path)
            let filename = url.lastPathComponent
            let directory = url.deletingLastPathComponent().relativePath.isEmpty
                ? nil
                : url.deletingLastPathComponent().relativePath + "/"

            return AutoCompleteSuggestion(
                id: entry.path,
                icon: iconName(for: entry),
                title: filename,
                subtitle: directory,
                insertText: entry.path
            )
        }
    }

    private func iconName(for entry: StatusEntry) -> String {
        switch entry.indexStatus == .unmodified ? entry.workdirStatus : entry.indexStatus {
        case .added:     return "plus.circle"
        case .deleted:   return "minus.circle"
        case .renamed:   return "arrow.right.circle"
        default:         return "doc.text"
        }
    }

    // MARK: Private — Template Suggestions

    /// Built-in templates; a future version could load these from SwiftData.
    private func templateSuggestions(query: String) -> [AutoCompleteSuggestion] {
        let builtIn: [(String, String, String)] = [
            // (id, name, prefix)
            ("conventional-feat",     "feat: New Feature",          "feat: "),
            ("conventional-fix",      "fix: Bug Fix",                "fix: "),
            ("conventional-docs",     "docs: Documentation",         "docs: "),
            ("conventional-style",    "style: Formatting",           "style: "),
            ("conventional-refactor", "refactor: Code Refactoring",  "refactor: "),
            ("conventional-test",     "test: Tests",                 "test: "),
            ("conventional-chore",    "chore: Maintenance",          "chore: "),
            ("conventional-perf",     "perf: Performance",           "perf: "),
            ("conventional-ci",       "ci: CI/CD",                   "ci: "),
        ]

        let filtered = query.isEmpty
            ? builtIn
            : builtIn.filter {
                $0.1.lowercased().contains(query) || $0.2.lowercased().contains(query)
            }

        return filtered.map { id, name, prefix in
            AutoCompleteSuggestion(
                id: id,
                icon: "text.badge.plus",
                title: name,
                subtitle: prefix,
                insertText: prefix
            )
        }
    }

    // MARK: Private — Default Preview Profiles

    /// Seed ``availableProfiles`` with sensible preview data so that SwiftUI
    /// Previews and plain `init` sites always have a usable profile without
    /// requiring a SwiftData container.
    private func loadDefaultPreviewProfiles() {
        let defaults: [UserProfileData] = [
            UserProfileData(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Your Name",
                email: "you@example.com",
                signingKeyID: nil,
                isDefault: true
            ),
        ]
        loadProfiles(from: defaults)
    }

    // MARK: Private

    private func loadDiff(for entry: StatusEntry) async {
        isDiffLoading = true
        defer { isDiffLoading = false }
        do {
            currentDiff = try await repository.diff(
                for: entry,
                staged: showingStaged,
                ignoreWhitespace: ignoreWhitespace
            )
        } catch {
            currentDiff = nil
            errorMessage = error.localizedDescription
        }
    }
}
