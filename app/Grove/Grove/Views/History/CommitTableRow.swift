// Views/History/CommitTableRow.swift
// Grove

import SwiftUI

/// How History lists commits.
enum HistoryLayout: String, CaseIterable, Identifiable {
    case graph, table

    var id: Self { self }
    var title: String { self == .graph ? "Graph" : "Table" }
    var symbol: String { self == .graph ? "point.3.connected.trianglepath.dotted" : "tablecells" }
}

/// Column widths shared by the table's header and rows.
enum CommitTableColumns {
    static let author: CGFloat = 110
    static let date: CGFloat = 92
    static let sha: CGFloat = 62
}

/// Column titles above the table layout.
struct CommitTableHeader: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Subject").frame(maxWidth: .infinity, alignment: .leading)
            Text("Author").frame(width: CommitTableColumns.author, alignment: .leading)
            Text("Date").frame(width: CommitTableColumns.date, alignment: .leading)
            Text("SHA").frame(width: CommitTableColumns.sha, alignment: .leading)
        }
        .font(.sectionLabel)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 26)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }
}

/// One commit as a compact table row: refs and subject, author, date, SHA.
struct CommitTableRow: View {
    let commit: CommitInfo
    var branches: [BranchInfo] = []
    var tags: [TagInfo] = []
    var syncState: CommitSyncState?
    var isSelected = false

    static let height: CGFloat = 26

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                CommitRefLabels(branches: branches, tags: tags)
                Text(commit.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(-1)
                if let syncState {
                    Image(systemName: syncState.symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .help(syncState.label)
                        .accessibilityLabel(syncState.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(commit.authorName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: CommitTableColumns.author, alignment: .leading)
            Text(commit.authorDate.commitRelative())
                .lineLimit(1)
                .frame(width: CommitTableColumns.date, alignment: .leading)
            Text(commit.shortSHA)
                .frame(width: CommitTableColumns.sha, alignment: .leading)
        }
        .font(.monoCaption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Self.height)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(Theme.selectionFill)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 0) {
        CommitTableHeader()
        ForEach(MockData.commits.prefix(8)) { commit in
            CommitTableRow(commit: commit,
                           branches: MockData.branches.filter { $0.targetSHA == commit.id },
                           tags: MockData.tags.filter { $0.targetSHA == commit.id },
                           isSelected: commit.id == MockData.commits[1].id)
        }
    }
    .frame(width: 560)
    .panel()
    .padding()
    .background(Theme.background)
}
