// Stashes/StashDetailPanel.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// The selected stash: its message and actions over the changes it holds.
struct StashDetailPanel: View {
    @Environment(\.gitStyle) private var style
    let viewModel: StashesViewModel
    let options: GitDiffOptions?
    let present: (GitDialog) -> Void

    var body: some View {
        Group {
            if let stash = viewModel.selectedStash {
                VStack(spacing: 0) {
                    header(stash)
                    Rectangle().fill(style.border).frame(height: 0.5)
                    // Untracked files live in the stash's third parent, so their image diff is missing a side.
                    GitChangesetBrowser(files: viewModel.stashDiffs, selectedPath: viewModel.selectedFilePath,
                                        isLoading: viewModel.isLoadingDiff, emptyTitle: "Empty Stash",
                                        images: .commit(stash.sha, in: viewModel.repository), options: options) {
                        viewModel.selectFile($0)
                    }
                }
            } else {
                GitEmptyState(systemImage: "tray.2", title: "No Stash Selected", subtitle: "Select a stash to see the changes it holds.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gitPanel()
    }

    private func header(_ stash: StashEntry) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: GitMetrics.Spacing.md) {
                summary(stash)
                Spacer(minLength: GitMetrics.Spacing.md)
                buttons(stash)
            }
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.sm) {
                summary(stash)
                buttons(stash)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GitMetrics.Spacing.lg)
    }

    private func summary(_ stash: StashEntry) -> some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
            Text(stash.displayMessage)
                .font(style.font(17, .semibold))
                .foregroundStyle(style.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack(spacing: GitMetrics.Spacing.md) {
                Text("stash@{\(stash.id)}")
                Text(String(stash.sha.prefix(7))).textSelection(.enabled)
                if viewModel.onRevealInHistory != nil {
                    Button { Task { await viewModel.revealBaseInHistory(stash) } } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .gitClickable()
                    .help("Reveal the commit this stash was made on in History")
                    .accessibilityLabel("Reveal base commit in History")
                }
                if let branch = stash.branchName { Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1) }
                Text(stash.date.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
            }
            .font(style.monoCaption)
            .foregroundStyle(style.textSecondary)
        }
    }

    private func buttons(_ stash: StashEntry) -> some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Button("Drop", role: .destructive) { viewModel.request(.drop, on: stash) }
            Button("Pop") { viewModel.request(.pop, on: stash) }
            Button("Apply") { viewModel.request(.apply, on: stash) }
                .buttonStyle(.borderedProminent)
            Menu {
                StashMenu(viewModel: viewModel, stash: stash, present: present)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .gitClickable()
            .accessibilityLabel("More")
        }
        .disabled(viewModel.isPerforming)
        .fixedSize()
    }
}
#endif
