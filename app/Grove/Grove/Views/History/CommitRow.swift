// Views/History/CommitRow.swift
// Grove

import SwiftUI

/// One commit in the history list: graph lanes, avatar, refs + subject, and a mono meta line.
struct CommitRow: View {
    let commit: CommitInfo
    var branches: [BranchInfo] = []
    var tags: [TagInfo] = []
    /// `nil` hides the graph, e.g. while the list is filtered and lanes would be misleading.
    var graphNode: GraphNode?
    var maxGraphColumns = 1
    var isHead = false
    var isSelected = false

    static let height: CGFloat = 46

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let graphNode {
                CommitGraphColumn(node: graphNode, maxColumns: maxGraphColumns, isHead: isHead)
            }
            AvatarView(name: commit.authorName, email: commit.authorEmail, size: .medium,
                       tint: graphNode.map { Theme.laneColor($0.colorIndex) })
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(branches.prefix(3)) { BranchLabel(branch: $0) }
                    ForEach(tags.prefix(2)) { BranchLabel(tag: $0) }
                    Text(commit.summary)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
                HStack(spacing: Theme.Spacing.xs) {
                    Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.authorDate.commitRelative())")
                        .lineLimit(1)
                    if commit.isMerge {
                        Image(systemName: "arrow.triangle.merge").accessibilityLabel("Merge commit")
                    }
                    if commit.isSigned {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                            .accessibilityLabel("Signed")
                    }
                }
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, graphNode == nil ? Theme.Spacing.md : Theme.Spacing.sm)
        .padding(.trailing, Theme.Spacing.md)
        .frame(height: Self.height)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.selectionFill)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.vertical, 1)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    let commits = MockData.commits
    let nodes = CommitGraphBuilder().buildGraph(from: commits)
    let columns = (nodes.map(\.column).max() ?? 0) + 1
    return VStack(spacing: 0) {
        ForEach(Array(zip(commits.prefix(8), nodes)), id: \.0.id) { commit, node in
            CommitRow(commit: commit,
                      branches: MockData.branches.filter { $0.targetSHA == commit.id },
                      tags: MockData.tags.filter { $0.targetSHA == commit.id },
                      graphNode: node, maxGraphColumns: columns,
                      isHead: commit.id == commits.first?.id, isSelected: commit.id == commits[1].id)
        }
    }
    .frame(width: 520)
    .panel()
    .padding()
    .background(Theme.background)
}
