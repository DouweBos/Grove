// Views/History/CommitDetailHeader.swift
// Grove

import SwiftUI

/// Subject, body and metadata of the selected commit.
struct CommitDetailHeader: View {
    @Environment(HistoryViewModel.self) private var viewModel
    let commit: CommitInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                AvatarView(name: commit.authorName, email: commit.authorEmail, size: .large,
                           tint: viewModel.graphNodes[commit.id].map { Theme.laneColor($0.colorIndex) })
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(commit.summary)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(commit.authorName).font(.rowTitle)
                        Text("· \(commit.authorDate.commitRelative())")
                            .font(.monoCaption)
                            .foregroundStyle(Theme.textSecondary)
                        if let signature = viewModel.selectedSignature {
                            VerifiedBadge(status: signature)
                        }
                    }
                }
            }
            if let body = commit.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Spacing.md, verticalSpacing: 6) {
            let refs = viewModel.branches(at: commit)
            let tags = viewModel.tags(at: commit)
            if !refs.isEmpty || !tags.isEmpty {
                row("Refs") {
                    FlowRow {
                        ForEach(refs) { BranchLabel(branch: $0) }
                        ForEach(tags) { BranchLabel(tag: $0) }
                    }
                }
            }
            row("Author") { person(commit.authorName, commit.authorEmail) }
            row("Date") { mono(commit.authorDate.commitTimestamp) }
            if commit.committerEmail != commit.authorEmail || commit.committerName != commit.authorName {
                row("Committer") { person(commit.committerName, commit.committerEmail) }
            }
            if abs(commit.committerDate.timeIntervalSince(commit.authorDate)) > 60 {
                row("Committed") { mono(commit.committerDate.commitTimestamp) }
            }
            row("SHA") {
                HStack(spacing: Theme.Spacing.xs) {
                    mono(commit.id).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    CopyButton(value: commit.id, help: "Copy SHA", confirmation: "Copied SHA")
                }
            }
            row(commit.parentIDs.count > 1 ? "Parents" : "Parent") {
                if commit.parentIDs.isEmpty {
                    Text("None (root commit)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(commit.parentIDs, id: \.self) { parent in
                            Button(String(parent.prefix(7))) { Task { await viewModel.selectCommit(id: parent) } }
                                .buttonStyle(.link)
                                .font(.monoCaption)
                                .help("Show parent commit")
                        }
                    }
                }
            }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .gridColumnAlignment(.trailing)
            content()
        }
    }

    private func person(_ name: String, _ email: String) -> some View {
        (Text(name).foregroundStyle(Theme.textPrimary) + Text("  \(email)").foregroundStyle(Theme.textSecondary))
            .font(.system(size: 12))
            .lineLimit(1)
            .textSelection(.enabled)
    }

    private func mono(_ text: String) -> Text {
        Text(text).font(.monoCaption).foregroundStyle(Theme.textPrimary)
    }
}

/// Wraps its children onto new lines when they don't fit.
struct FlowRow: Layout {
    var spacing: CGFloat = Theme.Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return CommitDetailHeader(commit: MockData.commits[0])
        .environment(vm)
        .padding()
        .frame(width: 520)
        .background(Theme.surface)
}
