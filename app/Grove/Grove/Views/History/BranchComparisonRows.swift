// Views/History/BranchComparisonRows.swift
// Grove

import AppKit
import SwiftUI

struct ComparisonCommitRow: View {
    let commit: CommitInfo

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AvatarView(name: commit.authorName, email: commit.authorEmail, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(.rowTitle).lineLimit(1)
                Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.authorDate.commitRelative())")
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if commit.isMerge {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 44)
        .contextMenu {
            Button("Copy Commit SHA") {
                GroveClipboard.copy(commit.id)
            }
        }
    }
}

struct ComparisonFileRow: View {
    let file: ChangedFileStat

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "doc")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text(file.path)
                .font(.monoCaption)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: Theme.Spacing.sm)
            if let additions = file.additions, let deletions = file.deletions {
                DiffStatsLabel(stats: DiffStats(additions: additions, deletions: deletions))
            } else {
                Text("binary").font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 26)
    }
}

/// Section header inside the comparison list; collapsible so a long side doesn't bury the other.
struct ComparisonSectionHeader: View {
    let title: String
    let symbol: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                SectionLabel(title: title, count: count)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
    }
}

#Preview {
    VStack(spacing: 0) {
        ComparisonSectionHeader(title: "Only in feature", symbol: "arrow.right", count: 2, isExpanded: .constant(true))
        ForEach(MockData.commits.prefix(2)) { ComparisonCommitRow(commit: $0) }
        ComparisonFileRow(file: ChangedFileStat(path: "Sources/App/Feature.swift", additions: 12, deletions: 3))
        ComparisonFileRow(file: ChangedFileStat(path: "Assets/icon.png", additions: nil, deletions: nil))
    }
    .frame(width: 520)
    .panel()
    .padding()
    .background(Theme.background)
}
