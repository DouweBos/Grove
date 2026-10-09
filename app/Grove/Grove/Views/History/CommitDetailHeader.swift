// Views/History/CommitDetailHeader.swift
// Grove

import GroveKit
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

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return CommitDetailHeader(commit: MockData.commits[0])
        .environment(vm)
        .padding()
        .frame(width: 520)
        .background(Theme.surface)
}
