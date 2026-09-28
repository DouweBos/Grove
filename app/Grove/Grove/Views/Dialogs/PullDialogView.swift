// Views/Dialogs/PullDialogView.swift
// Grove

import SwiftUI

/// Pulls the checked-out branch's upstream into it.
struct PullDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    var onComplete: () -> Void = {}

    @State private var useRebase = false
    @State private var autoStash = false
    @State private var isPulling = false
    @State private var errorMessage: String?

    private var branch: BranchInfo? { repository.currentBranch }
    private var upstream: String? { branch?.upstreamShortName }

    var body: some View {
        DialogSheet(
            title: "Pull",
            message: "Fetches new commits from the upstream branch and integrates them into '\(branch?.name ?? "HEAD")'.",
            symbol: "arrow.down.to.line",
            progress: isPulling ? "Pulling from \(upstream ?? "remote")…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Pull",
            isPrimaryDisabled: upstream == nil,
            onCancel: { dismiss() },
            onPrimary: performPull
        ) {
            DialogCard {
                DialogField("From") {
                    if let upstream {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(upstream).font(.monoCaption)
                            if let branch, branch.behind > 0 {
                                StatusBadge(title: "\(branch.behind) behind", symbol: "arrow.down", tone: .caution)
                            }
                        }
                    } else {
                        Text("No upstream branch").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                }
                DialogOptionRow(
                    isOn: $useRebase,
                    label: "Rebase Instead of Merge",
                    description: "Replays your local commits on top of the fetched ones."
                )
                DialogOptionRow(
                    isOn: $autoStash,
                    label: "Stash Local Changes",
                    description: "Stashes uncommitted changes first and restores them afterwards."
                )
            }
            if upstream == nil {
                Banner(symbol: "exclamationmark.triangle",
                       message: "'\(branch?.name ?? "HEAD")' doesn't track a remote branch. Push it first to set one.")
            }
        }
    }

    private func performPull() {
        isPulling = true
        errorMessage = nil
        Task {
            do {
                let didStash = autoStash ? try await stashIfDirty(repository, message: "Grove: auto-stash before pull") : false
                try await repository.pull(remote: nil, rebase: useRebase, progress: nil)
                if didStash {
                    try await repository.stashApply(index: 0, drop: true)
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isPulling = false
                onComplete()
            }
        }
    }
}

#Preview {
    PullDialogView(repository: MockGitRepository())
}
