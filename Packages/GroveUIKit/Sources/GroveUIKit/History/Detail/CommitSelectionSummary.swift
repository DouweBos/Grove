// History/Detail/CommitSelectionSummary.swift
// GroveUIKit
//
// The detail pane for several commits: what they add up to, what can be done to all of them, then each one.

#if os(macOS)
import GroveKit
import SwiftUI

struct CommitSelectionSummary: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    let viewModel: HistoryViewModel
    let actions: CommitActions
    /// Newest first, as listed.
    let commits: [CommitInfo]

    private static let listLimit = 50

    var body: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: "\(commits.count) Commits Selected")
            ScrollView {
                VStack(alignment: .leading, spacing: GitMetrics.Spacing.lg) {
                    facts
                    buttons
                    VStack(spacing: GitMetrics.Spacing.xs) {
                        ForEach(commits.prefix(Self.listLimit)) { CommitSummaryTile(commit: $0) }
                        if commits.count > Self.listLimit {
                            Text("and \(commits.count - Self.listLimit) more")
                                .font(style.monoCaption)
                                .foregroundStyle(style.textSecondary)
                        }
                    }
                }
                .padding(GitMetrics.Spacing.lg)
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: GitMetrics.Spacing.md, verticalSpacing: GitMetrics.Spacing.sm) {
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
        .gitCard()
    }

    private var buttons: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Button("Squash \(commits.count) Commits") { viewModel.request(.squashCommits(commits)) }
                .disabled(!viewModel.canSquash(commits))
                .gitClickable()
            Button("Save as Patch") { Task { await actions.savePatch(commits) } }
                .disabled(!viewModel.canSavePatch(commits))
                .requires(.export)
                .gitClickable()
            Button("Copy SHAs") { actions.copySHAs() }
                .gitClickable()
        }
        .controlSize(.small)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(style.sectionLabel).foregroundStyle(style.textSecondary)
            Text(value).font(style.monoCaption).foregroundStyle(style.textPrimary).textSelection(.enabled)
        }
    }

    private func dateRange(from start: Date, to end: Date) -> String {
        let first = min(start, end).formatted(date: .abbreviated, time: .omitted)
        let last = max(start, end).formatted(date: .abbreviated, time: .omitted)
        return first == last ? first : "\(first) \u{2013} \(last)"
    }
}

/// The commit an action applies to, as a small tile.
struct CommitSummaryTile: View {
    @Environment(\.gitStyle) private var style
    let commit: CommitInfo

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            CommitAvatar(name: commit.authorName, email: commit.authorEmail, size: .small)
            Text(commit.summary).font(style.font(13, .medium)).foregroundStyle(style.textPrimary).lineLimit(1)
            Spacer(minLength: GitMetrics.Spacing.sm)
            Text(commit.shortSHA).font(style.monoCaption).foregroundStyle(style.textSecondary)
        }
        .padding(GitMetrics.Spacing.sm)
        .background(style.background, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile))
    }
}
#endif
