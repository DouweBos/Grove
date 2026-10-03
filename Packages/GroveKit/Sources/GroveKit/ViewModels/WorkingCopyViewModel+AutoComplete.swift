// ViewModels/WorkingCopyViewModel+AutoComplete.swift
// GroveKit
//
// Trigger detection and suggestions for the commit subject field
// (`#` issues, `c:` commits, backtick files, `/` templates).

import Foundation

// MARK: - AutoCompleteTrigger

/// Identifies which trigger character caused the autocomplete list to appear.
enum AutoCompleteTrigger: Equatable {
    /// `#` — issue and pull-request references.
    case issue
    /// `c:` — recent commit SHAs / summaries.
    case commit
    /// `` ` `` — filenames from the current status entries.
    case filename
    /// `/` — commit message templates.
    case template
    /// `:` at the start or after a space — gitmoji codes, inserting the emoji.
    case gitmoji
}

// MARK: - AutoCompleteSuggestion

/// A single row in the autocomplete dropdown.
struct AutoCompleteSuggestion: Identifiable, Sendable, Equatable {
    /// Stable unique identifier (typically the `insertText`).
    let id: String
    /// SF Symbol name shown on the leading edge.
    let icon: String
    /// Primary display text.
    let title: String
    /// Optional secondary information shown in a lighter style.
    let subtitle: String?
    /// The text that replaces the trigger sequence in the subject field.
    let insertText: String
}

extension WorkingCopyViewModel {


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
        autoCompleteHighlight = autoCompleteSuggestions.first?.id
    }

    func highlightAutoComplete(_ id: String) {
        autoCompleteHighlight = id
    }

    func moveAutoCompleteHighlight(by delta: Int) {
        let suggestions = autoCompleteSuggestions
        guard !suggestions.isEmpty else { return }
        let current = suggestions.firstIndex { $0.id == autoCompleteHighlight } ?? 0
        autoCompleteHighlight = suggestions[(current + delta + suggestions.count) % suggestions.count].id
    }

    /// Return in the subject field; false when no list is showing, so Return moves on to the description.
    func acceptAutoComplete() -> Bool {
        guard isAutoCompleteVisible,
              let suggestion = autoCompleteSuggestions.first(where: { $0.id == autoCompleteHighlight }) ?? autoCompleteSuggestions.first
        else { return false }
        applyAutoComplete(suggestion)
        return true
    }

    /// Apply a chosen suggestion: replace the trigger + query with `insertText`.
    func applyAutoComplete(_ suggestion: AutoCompleteSuggestion) {
        guard let trigger = autoCompleteTrigger else { return }
        let triggerPrefix = prefix(for: trigger)
        // Find the last occurrence of the trigger prefix and replace from there.
        if let range = commitSubject.range(of: triggerPrefix, options: .backwards) {
            // Replace the trigger and the query typed after it.
            commitSubject = String(commitSubject[..<range.lowerBound]) + suggestion.insertText
        }
        if trigger == .template { completeTemplate(suggestion) }
        dismissAutoComplete()
    }

    /// Hide the autocomplete dropdown without modifying the subject text.
    func dismissAutoComplete() {
        autoCompleteTrigger = nil
        autoCompleteSuggestions = []
        autoCompleteHighlight = nil
    }

    // MARK: Private — Autocomplete Detection

    /// Returns the matched ``AutoCompleteTrigger`` and the query text that follows it,
    /// or `nil` if the current text does not end with a recognised trigger sequence.
    private func detectTrigger(in text: String) -> (AutoCompleteTrigger, String)? {
        if let query = Self.gitmojiQuery(in: text) { return (.gitmoji, query) }
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
        case .gitmoji:  return ":"
        }
    }

    /// The code typed after a `:` that starts the text or follows a space, so `feat:` never triggers it.
    static func gitmojiQuery(in text: String) -> String? {
        guard let colon = text.lastIndex(of: ":") else { return nil }
        guard colon == text.startIndex || text[text.index(before: colon)].isWhitespace else { return nil }
        let query = text[text.index(after: colon)...]
        guard query.allSatisfy({ $0.isLetter || $0.isNumber || "_+-".contains($0) }) else { return nil }
        return String(query)
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
        case .gitmoji:
            return Gitmoji.search(query).prefix(12).map { gitmoji in
                AutoCompleteSuggestion(id: gitmoji.code, icon: "face.smiling", title: "\(gitmoji.emoji)  \(gitmoji.code)",
                                       subtitle: gitmoji.description, insertText: gitmoji.emoji + " ")
            }
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
            AutoCompleteSuggestion(
                id: entry.path,
                icon: iconName(for: entry),
                title: entry.fileName,
                subtitle: entry.directory.isEmpty ? nil : entry.directory,
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

}
