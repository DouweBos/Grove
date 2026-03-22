// Views/WorkingCopy/CommitAutoCompleteView.swift
// Grove
//
// Floating suggestion list that appears below the commit subject field
// when the user types a trigger character.
//
// Triggers:
//   #     → issue / PR references extracted from branch names
//   c:    → recent commit SHAs and summaries
//   `     → filenames from the current working-tree status
//   /     → commit message templates

import SwiftUI

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

// MARK: - CommitAutoCompleteView

/// A floating list of commit message suggestions anchored below the subject field.
///
/// Place this view inside an `.overlay` or `.background` on the subject
/// `TextField` row so it can appear at the correct position without
/// disrupting the layout.
///
/// ```swift
/// TextField("Commit Subject", text: $vm.commitSubject)
///     .overlay(alignment: .topLeading) {
///         CommitAutoCompleteView(
///             trigger: vm.autoCompleteTrigger,
///             suggestions: vm.autoCompleteSuggestions,
///             onSelect: { vm.applyAutoComplete($0) },
///             onDismiss: { vm.dismissAutoComplete() }
///         )
///         .offset(y: 24)
///     }
/// ```
struct CommitAutoCompleteView: View {

    // MARK: Inputs

    /// Which trigger is active (controls the header label).
    let trigger: AutoCompleteTrigger
    /// Current list of matching suggestions.
    let suggestions: [AutoCompleteSuggestion]
    /// Called when the user taps or keyboards-selects a row.
    let onSelect: (AutoCompleteSuggestion) -> Void
    /// Called when the user presses Escape or the list should close.
    let onDismiss: () -> Void

    // MARK: State

    @State private var highlightedID: String?

    // MARK: Constants

    private let maxVisibleRows = 6
    private let rowHeight: CGFloat = 36

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            triggerHeader
            Divider()
            suggestionList
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .onAppear { highlightedID = suggestions.first?.id }
        .onChange(of: suggestions) { _, new in
            highlightedID = new.first?.id
        }
        // Keyboard: arrow navigation + confirm + dismiss
        .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
        .onKeyPress(.return) { confirmHighlighted();   return .handled }
        .onKeyPress(.escape) { onDismiss();            return .handled }
    }

    // MARK: Trigger Header

    private var triggerHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: triggerIcon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(triggerLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Suggestion List

    private var suggestionList: some View {
        let visibleCount = min(suggestions.count, maxVisibleRows)
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        isHighlighted: suggestion.id == highlightedID
                    )
                    .onTapGesture { onSelect(suggestion) }
                    .onHover { hovering in
                        if hovering { highlightedID = suggestion.id }
                    }
                }
            }
        }
        .frame(height: CGFloat(visibleCount) * rowHeight)
    }

    // MARK: Helpers

    private var triggerIcon: String {
        switch trigger {
        case .issue:    return "number"
        case .commit:   return "arrow.triangle.branch"
        case .filename: return "doc.text"
        case .template: return "text.badge.plus"
        }
    }

    private var triggerLabel: String {
        switch trigger {
        case .issue:    return "Issues & Pull Requests"
        case .commit:   return "Recent Commits"
        case .filename: return "Changed Files"
        case .template: return "Commit Templates"
        }
    }

    private func moveHighlight(by delta: Int) {
        guard !suggestions.isEmpty else { return }
        let currentIndex = suggestions.firstIndex(where: { $0.id == highlightedID }) ?? 0
        let newIndex = (currentIndex + delta + suggestions.count) % suggestions.count
        highlightedID = suggestions[newIndex].id
    }

    private func confirmHighlighted() {
        guard let id = highlightedID,
              let suggestion = suggestions.first(where: { $0.id == id }) else { return }
        onSelect(suggestion)
    }
}

// MARK: - SuggestionRow

/// A single row inside ``CommitAutoCompleteView``.
private struct SuggestionRow: View {

    let suggestion: AutoCompleteSuggestion
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 12))
                .foregroundStyle(isHighlighted ? .white : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHighlighted ? .white : .primary)
                    .lineLimit(1)
                if let subtitle = suggestion.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(isHighlighted ? .white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            isHighlighted
                ? Color.accentColor
                : Color.clear,
            in: Rectangle()
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview("Issue Suggestions") {
    CommitAutoCompleteView(
        trigger: .issue,
        suggestions: [
            AutoCompleteSuggestion(
                id: "PROJ-123",
                icon: "number",
                title: "PROJ-123",
                subtitle: "feature/PROJ-123-auth-flow",
                insertText: "PROJ-123"
            ),
            AutoCompleteSuggestion(
                id: "42",
                icon: "number",
                title: "#42",
                subtitle: "feature/dark-mode",
                insertText: "#42"
            )
        ],
        onSelect: { _ in },
        onDismiss: {}
    )
    .padding()
    .frame(width: 400)
}

#Preview("Commit Suggestions") {
    CommitAutoCompleteView(
        trigger: .commit,
        suggestions: [
            AutoCompleteSuggestion(
                id: "a1b2c3d",
                icon: "arrow.triangle.branch",
                title: "feat: add OAuth2 authentication flow",
                subtitle: "a1b2c3d",
                insertText: "a1b2c3d"
            ),
            AutoCompleteSuggestion(
                id: "b2c3d4e",
                icon: "arrow.triangle.branch",
                title: "refactor: split AuthManager into focused services",
                subtitle: "b2c3d4e",
                insertText: "b2c3d4e"
            )
        ],
        onSelect: { _ in },
        onDismiss: {}
    )
    .padding()
    .frame(width: 400)
}

#Preview("Filename Suggestions") {
    CommitAutoCompleteView(
        trigger: .filename,
        suggestions: [
            AutoCompleteSuggestion(
                id: "Sources/App/AuthManager.swift",
                icon: "doc.text",
                title: "AuthManager.swift",
                subtitle: "Sources/App/",
                insertText: "Sources/App/AuthManager.swift"
            ),
            AutoCompleteSuggestion(
                id: "Sources/App/TokenStore.swift",
                icon: "doc.text",
                title: "TokenStore.swift",
                subtitle: "Sources/App/",
                insertText: "Sources/App/TokenStore.swift"
            )
        ],
        onSelect: { _ in },
        onDismiss: {}
    )
    .padding()
    .frame(width: 400)
}

#Preview("Template Suggestions") {
    CommitAutoCompleteView(
        trigger: .template,
        suggestions: [
            AutoCompleteSuggestion(
                id: "conventional",
                icon: "text.badge.plus",
                title: "Conventional Commit",
                subtitle: "feat: ",
                insertText: "feat: "
            ),
            AutoCompleteSuggestion(
                id: "bugfix",
                icon: "text.badge.plus",
                title: "Bug Fix",
                subtitle: "fix: ",
                insertText: "fix: "
            )
        ],
        onSelect: { _ in },
        onDismiss: {}
    )
    .padding()
    .frame(width: 400)
}
