// Views/History/CommitSelectionSummary.swift
// Grove

import SwiftUI

/// Detail pane for a multi-selection: count, SHA range, authors and dates, then each commit.
struct CommitSelectionSummary: View {
    /// Newest first, as listed.
    let commits: [CommitInfo]

    private static let listLimit = 50

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "\(commits.count) Commits Selected")
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    facts
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(commits.prefix(Self.listLimit)) { CommitSummaryTile(commit: $0) }
                        if commits.count > Self.listLimit {
                            Text("and \(commits.count - Self.listLimit) more")
                                .font(.monoCaption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.md, verticalSpacing: Theme.Spacing.sm) {
            if let newest = commits.first, let oldest = commits.last {
                fact("Range", "\(oldest.shortSHA)\u{2026}\(newest.shortSHA)")
                fact("Dates", dateRange(from: oldest.authorDate, to: newest.authorDate))
            }
            let authors = Set(commits.map(\.authorName)).sorted()
            fact(authors.count == 1 ? "Author" : "Authors", authors.joined(separator: ", "))
            let merges = commits.filter(\.isMerge).count
            if merges > 0 { fact("Merges", "\(merges)") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(.sectionLabel).foregroundStyle(Theme.textSecondary)
            Text(value).font(.monoCaption).foregroundStyle(Theme.textPrimary).textSelection(.enabled)
        }
    }

    private func dateRange(from start: Date, to end: Date) -> String {
        let first = min(start, end).formatted(date: .abbreviated, time: .omitted)
        let last = max(start, end).formatted(date: .abbreviated, time: .omitted)
        return first == last ? first : "\(first) \u{2013} \(last)"
    }
}

#Preview {
    CommitSelectionSummary(commits: Array(MockData.commits.prefix(4)))
        .frame(width: 520, height: 520)
        .panel()
        .padding()
        .background(Theme.background)
}
