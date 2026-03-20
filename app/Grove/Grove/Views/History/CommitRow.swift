// Views/History/CommitRow.swift
// Grove

import SwiftUI

/// A single row in the commit list.
///
/// Shows a graph dot, commit message summary, author, relative date, and branch/tag pills.
struct CommitRow: View {

    let commit: CommitInfo

    /// Branches that point to this commit.
    var branches: [BranchInfo] = []
    /// Tags that point to this commit.
    var tags: [TagInfo] = []

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Graph dot — simple colored circle (full graph rendering in future)
            Circle()
                .fill(graphColor)
                .frame(width: 10, height: 10)
                .padding(.leading, 2)

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

    private var graphColor: Color {
        // Simple lane color based on SHA for visual variety
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .yellow]
        let index = abs(commit.id.hashValue) % colors.count
        return colors[index]
    }
}

#Preview {
    let commits = MockData.commits
    let branches = MockData.branches

    return List {
        ForEach(commits.prefix(5)) { commit in
            CommitRow(
                commit: commit,
                branches: branches.filter { $0.targetSHA == commit.id },
                tags: MockData.tags.filter { $0.targetSHA == commit.id }
            )
        }
    }
    .listStyle(.plain)
    .frame(width: 500, height: 250)
}
