// Views/History/CommitRow.swift
// Grove

import SwiftUI

/// A single row in the commit list.
///
/// Shows a graph column at the leading edge (lanes, edges, and a commit circle),
/// followed by branch/tag pills, the commit message, author, and relative date.
struct CommitRow: View {

    let commit: CommitInfo

    /// Branches that point to this commit.
    var branches: [BranchInfo] = []
    /// Tags that point to this commit.
    var tags: [TagInfo] = []

    /// Pre-computed graph node from ``HistoryViewModel``.
    /// When `nil` a simple colored circle is shown as a fallback.
    var graphNode: GraphNode?
    /// Total active columns at the widest point — drives the graph column width.
    var maxGraphColumns: Int = 1

    // MARK: - Row height

    /// The list row height that callers should match via `.frame(height:)`.
    static let rowHeight: CGFloat = 32

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 8) {

            // MARK: Graph column
            if let node = graphNode {
                CommitGraphColumn(
                    node: node,
                    maxColumns: maxGraphColumns,
                    rowHeight: Self.rowHeight
                )
            } else {
                // Fallback: simple colored dot while graph is loading.
                Circle()
                    .fill(fallbackColor)
                    .frame(width: 10, height: 10)
                    .padding(.leading, 2)
            }

            // MARK: Commit metadata
            VStack(alignment: .leading, spacing: 3) {
                // Message line with branch/tag pills
                HStack(spacing: 4) {
                    // Branch/tag labels
                    ForEach(branches.prefix(3), id: \.id) { branch in
                        BranchLabel(branch: branch)
                    }
                    ForEach(tags.prefix(2), id: \.id) { tag in
                        BranchLabel(tag: tag)
                    }

                    Text(commit.summary)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // Author + date
                HStack(spacing: 4) {
                    Text(commit.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(commit.authorDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if commit.isSigned {
                        Image(systemName: "checkmark.seal.fill")
                            .imageScale(.small)
                            .foregroundStyle(.green)
                    }

                    if commit.isMerge {
                        Image(systemName: "arrow.triangle.merge")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Short SHA
            Text(commit.shortSHA)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    /// Color used when no ``GraphNode`` is available yet.
    private var fallbackColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .yellow]
        var hash: UInt64 = 5381
        for byte in commit.id.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let index = Int(hash % UInt64(colors.count))
        return colors[index]
    }
}

// MARK: - Preview

#Preview {
    // Build real graph nodes from mock data so the preview exercises the
    // full pipeline: CommitGraphBuilder -> GraphNode -> CommitGraphColumn.
    //
    // CommitGraphBuilder is @MainActor so we pre-build on the MainActor
    // inside a PreviewProvider-style wrapper using @MainActor isolation.
    @MainActor
    struct PreviewContent: View {
        private let commits  = MockData.commits
        private let branches = MockData.branches
        private let tags     = MockData.tags
        private let nodeMap: [String: GraphNode]
        private let maxCols: Int

        init() {
            let builder = CommitGraphBuilder()
            let nodes = builder.buildGraph(from: commits)
            nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            maxCols = (nodes.map(\.column).max().map { $0 + 1 }) ?? 1
        }

        var body: some View {
            List {
                ForEach(commits.prefix(8)) { commit in
                    CommitRow(
                        commit: commit,
                        branches: branches.filter { $0.targetSHA == commit.id },
                        tags: tags.filter { $0.targetSHA == commit.id },
                        graphNode: nodeMap[commit.id],
                        maxGraphColumns: maxCols
                    )
                }
            }
            .listStyle(.plain)
            .frame(width: 520, height: 280)
        }
    }

    return PreviewContent()
}
