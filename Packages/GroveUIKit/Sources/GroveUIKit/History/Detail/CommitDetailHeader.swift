// History/Detail/CommitDetailHeader.swift
// GroveUIKit
//
// Subject, body and metadata of the selected commit.

#if os(macOS)
import GroveKit
import SwiftUI

struct CommitDetailHeader: View {
    @Environment(\.gitStyle) private var style
    let viewModel: HistoryViewModel
    let commit: CommitInfo

    var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.md) {
            HStack(alignment: .top, spacing: GitMetrics.Spacing.md) {
                CommitAvatar(name: commit.authorName, email: commit.authorEmail, size: .large,
                             tint: viewModel.graphNodes[commit.id].map { style.lane($0.colorIndex) })
                VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
                    Text(commit.summary)
                        .font(style.font(16, .semibold))
                        .foregroundStyle(style.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: GitMetrics.Spacing.xs) {
                        Text(commit.authorName).font(style.font(13, .medium)).foregroundStyle(style.textPrimary)
                        Text("· \(commit.authorDate.commitRelative())")
                            .font(style.monoCaption)
                            .foregroundStyle(style.textSecondary)
                        signature
                    }
                }
            }
            if let body = commit.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                Text(body)
                    .font(style.font(13))
                    .foregroundStyle(style.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var signature: some View {
        if let status = viewModel.selectedSignature {
            VerifiedBadge(status: status)
        } else if commit.isSigned {
            GitStatusBadge(title: "Checking", symbol: "seal", tone: .neutral)
        }
    }

    private var metadata: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: GitMetrics.Spacing.md, verticalSpacing: 6) {
            let refs = viewModel.branches(at: commit)
            let tags = viewModel.tags(at: commit)
            if !refs.isEmpty || !tags.isEmpty {
                row("Refs") {
                    HistoryFlowRow {
                        ForEach(refs) { GitBranchLabel(branch: $0) }
                        ForEach(tags) { GitBranchLabel(tag: $0) }
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
                HStack(spacing: GitMetrics.Spacing.xs) {
                    mono(commit.id).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    HistoryCopyButton(value: { commit.id }, help: "Copy SHA", confirmation: "Copied SHA")
                }
            }
            row(commit.parentIDs.count > 1 ? "Parents" : "Parent") { parents }
        }
    }

    @ViewBuilder
    private var parents: some View {
        if commit.parentIDs.isEmpty {
            Text("None (root commit)").font(style.font(12)).foregroundStyle(style.textSecondary)
        } else {
            HStack(spacing: GitMetrics.Spacing.sm) {
                ForEach(commit.parentIDs, id: \.self) { parent in
                    Button(String(parent.prefix(7))) { Task { await viewModel.selectCommit(id: parent) } }
                        .buttonStyle(.link)
                        .gitClickable()
                        .font(style.monoCaption)
                        .help("Show parent commit")
                }
            }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .font(style.font(12))
                .foregroundStyle(style.textSecondary)
                .gridColumnAlignment(.trailing)
            content()
        }
    }

    private func person(_ name: String, _ email: String) -> some View {
        (Text(name).foregroundStyle(style.textPrimary) + Text("  \(email)").foregroundStyle(style.textSecondary))
            .font(style.font(12))
            .lineLimit(1)
            .textSelection(.enabled)
    }

    private func mono(_ text: String) -> Text {
        Text(text).font(style.monoCaption).foregroundStyle(style.textPrimary)
    }
}
#endif
