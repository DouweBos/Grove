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
//   :     → gitmoji codes, inserting the emoji

import GroveKit
import SwiftUI

// MARK: - CommitAutoCompleteView

/// A floating list of commit message suggestions anchored below the subject field.
///
/// The subject field keeps keyboard focus and forwards arrows, Return and Escape
/// to the view model, which owns the highlighted row.
struct CommitAutoCompleteView: View {

    // MARK: Inputs

    /// Which trigger is active (controls the header label).
    let trigger: AutoCompleteTrigger
    /// Current list of matching suggestions.
    let suggestions: [AutoCompleteSuggestion]
    /// The row Return would pick.
    let highlightedID: String?
    /// Called when the user clicks a row.
    let onSelect: (AutoCompleteSuggestion) -> Void
    /// Called when the pointer moves over a row.
    let onHighlight: (String) -> Void

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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    // MARK: Trigger Header

    private var triggerHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: triggerIcon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text(triggerLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
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
                    .id(suggestion.id)
                    .onTapGesture { onSelect(suggestion) }
                    .onHover { hovering in
                        if hovering { onHighlight(suggestion.id) }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: .constant(highlightedID), anchor: .center)
        .frame(height: CGFloat(visibleCount) * rowHeight)
    }

    // MARK: Helpers

    private var triggerIcon: String {
        switch trigger {
        case .issue:    return "number"
        case .commit:   return "arrow.triangle.branch"
        case .filename: return "doc.text"
        case .template: return "text.badge.plus"
        case .gitmoji:  return "face.smiling"
        }
    }

    private var triggerLabel: String {
        switch trigger {
        case .issue:    return "Issues & Pull Requests"
        case .commit:   return "Recent Commits"
        case .filename: return "Changed Files"
        case .template: return "Commit Templates"
        case .gitmoji:  return "Gitmoji"
        }
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
                .foregroundStyle(isHighlighted ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle = suggestion.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            isHighlighted ? Theme.selectionFill : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
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
        highlightedID: "PROJ-123",
        onSelect: { _ in },
        onHighlight: { _ in }
    )
    .padding()
    .frame(width: 400)
}
