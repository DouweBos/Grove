// Views/Dialogs/PullDialogView.swift
// Grove

import SwiftUI

/// Pulls the checked-out branch's upstream into it.
struct PullDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    var onComplete: () -> Void = {}

    @State private var strategy: PullStrategy = .merge
    @State private var autoStash = false
    @State private var remotes: [RemoteInfo] = []
    @State private var progressTitle: String?
    @State private var errorMessage: String?

    private var branch: BranchInfo? { repository.currentBranch }
    private var upstream: String? { branch?.upstreamShortName }

    var body: some View {
        DialogSheet(
            title: "Pull",
            message: "Fetches new commits from the upstream branch and integrates them into '\(branch?.name ?? "HEAD")'.",
            symbol: "arrow.down.to.line",
            progress: progressTitle,
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
                PullStrategyField(strategy: $strategy)
                DialogOptionRow(
                    isOn: $autoStash,
                    label: "Stash Local Changes",
                    description: "Stashes uncommitted changes first and restores them afterwards."
                )
            }
            if upstream == nil {
                noUpstreamBanner
            }
        }
        .task {
            strategy = await repository.defaultPullStrategy()
            remotes = (try? await repository.remotes()) ?? []
        }
    }

    @ViewBuilder
    private var noUpstreamBanner: some View {
        let name = branch?.name ?? "HEAD"
        if let remote = remotes.first?.name, branch != nil {
            Banner(symbol: "exclamationmark.triangle",
                   message: "'\(name)' doesn't track a remote branch yet. Push it to \(remote) to start tracking.",
                   actionTitle: "Push to \(remote)",
                   action: { performPushSettingUpstream(remote: remote) })
        } else {
            Banner(symbol: "exclamationmark.triangle",
                   message: "'\(name)' doesn't track a remote branch, and there's no remote to push it to.")
        }
    }

    private func performPull() {
        run("Pulling from \(upstream ?? "remote")…") {
            let didStash = autoStash ? try await stashIfDirty(repository, message: "Grove: auto-stash before pull") : false
            try await repository.pull(remote: nil, strategy: strategy, progress: nil)
            if didStash {
                try await repository.stashApply(index: 0, drop: true)
            }
        }
    }

    private func performPushSettingUpstream(remote: String) {
        run("Pushing to \(remote)…") {
            try await repository.push(remote: remote, forceWithLease: false, setUpstream: true, progress: nil)
        }
    }

    private func run(_ title: String, _ operation: @escaping () async throws -> Void) {
        progressTitle = title
        errorMessage = nil
        Task {
            do {
                try await operation()
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                progressTitle = nil
                onComplete()
            }
        }
    }
}

/// Segmented merge / rebase / fast-forward picker shared by Pull and Sync.
struct PullStrategyField: View {
    @Binding var strategy: PullStrategy

    var body: some View {
        DialogField("Integrate") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Picker("Integrate", selection: $strategy) {
                    ForEach(PullStrategy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(strategy.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    PullDialogView(repository: MockGitRepository())
}
