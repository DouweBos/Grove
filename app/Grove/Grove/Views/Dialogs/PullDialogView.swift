// Views/Dialogs/PullDialogView.swift
// Grove

import SwiftUI

/// Pulls a remote branch into the checked-out branch: its upstream by default, or another one,
/// which with Rebase is the quick way to rebase onto e.g. `origin/main`.
struct PullDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    /// Last-read remotes and remote branches, so the sheet doesn't wait on git to list them.
    let refs: RepositoryRefs
    var onComplete: () -> Void = {}

    @State private var strategy: PullStrategy = .merge
    @State private var autoStash = false
    @State private var options = PullOptions()
    /// Remote branch to pull, as `remote/branch`.
    @State private var source: String?
    @State private var progressTitle: String?
    @State private var errorMessage: String?

    private var remotes: [RemoteInfo] { refs.remotes }
    private var remoteBranches: [BranchInfo] { refs.remoteBranches }
    private var branch: BranchInfo? { repository.currentBranch }
    private var upstream: String? { branch?.upstreamShortName }

    var body: some View {
        DialogSheet(
            title: "Pull",
            message: "Fetches a remote branch and integrates it into '\(branch?.name ?? "HEAD")'.",
            symbol: "arrow.down.to.line",
            progress: progressTitle,
            errorMessage: errorMessage,
            primaryTitle: "Pull",
            isPrimaryDisabled: source == nil,
            onCancel: { dismiss() },
            onPrimary: performPull
        ) {
            DialogCard {
                DialogField("From") {
                    HStack(spacing: Theme.Spacing.sm) {
                        PullSourcePicker(branches: remoteBranches, upstream: upstream, selection: $source)
                        if let branch, source == upstream, branch.behind > 0 {
                            StatusBadge(title: "\(branch.behind) behind", symbol: "arrow.down", tone: .caution)
                        }
                    }
                }
                PullStrategyField(strategy: $strategy)
                if let outcome {
                    Text(outcome)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DialogOptionRow(
                    isOn: $autoStash,
                    label: "Stash Local Changes",
                    description: "Stashes uncommitted changes first and restores them afterwards."
                )
            }
            DialogOptionsSection {
                DialogOptionRow(
                    isOn: $options.verifySignatures,
                    label: "Verify Signatures",
                    description: "The pull is aborted if the tip commit of the pulled branch isn't signed with a valid key."
                )
                .disabled(strategy == .rebase)
                DialogOptionRow(
                    isOn: $options.skipHooks,
                    label: "Skip Hooks",
                    description: "Bypasses the pre-merge-commit and commit-msg hooks."
                )
                .disabled(strategy == .rebase)
                if strategy == .rebase {
                    Text("Git ignores these options when rebasing.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if upstream == nil {
                noUpstreamBanner
            }
        }
        .task {
            source = PullSourcePicker.defaultSource(for: branch, in: remoteBranches)
            strategy = await repository.defaultPullStrategy()
        }
        .onChange(of: remoteBranches) { _, branches in
            if source == nil { source = PullSourcePicker.defaultSource(for: branch, in: branches) }
        }
    }

    @ViewBuilder
    private var noUpstreamBanner: some View {
        let name = branch?.name ?? "HEAD"
        if let remote = remotes.first?.name, branch != nil {
            Banner(symbol: "exclamationmark.triangle",
                   message: "'\(name)' doesn't track a remote branch yet. You can still pull any branch; push it to \(remote) to start tracking.",
                   actionTitle: "Push to \(remote)",
                   action: { performPushSettingUpstream(remote: remote) })
        } else {
            Banner(symbol: "exclamationmark.triangle",
                   message: "'\(name)' doesn't track a remote branch, and there's no remote to push it to.")
        }
    }

    /// Spells out a pull from something other than the upstream, since that changes what the branch becomes.
    private var outcome: String? {
        guard let source, source != upstream else { return nil }
        let name = branch?.name ?? "HEAD"
        switch strategy {
        case .rebase: return "Rebases '\(name)' onto \(source)."
        case .merge: return "Merges \(source) into '\(name)'."
        case .fastForwardOnly: return "Moves '\(name)' forward to \(source), if it hasn't diverged."
        }
    }

    /// `origin/feature/x` → ("origin", "feature/x"), matching against known remote names.
    private func split(_ source: String) -> (remote: String, branch: String)? {
        let remote = remotes.map(\.name).sorted { $0.count > $1.count }.first { source.hasPrefix($0 + "/") }
            ?? source.split(separator: "/", maxSplits: 1).first.map(String.init)
        guard let remote, source.count > remote.count + 1 else { return nil }
        return (remote, String(source.dropFirst(remote.count + 1)))
    }

    private func performPull() {
        guard let source else { return }
        run("Pulling from \(source)…") {
            let didStash = autoStash ? try await stashIfDirty(repository, message: "Grove: auto-stash before pull") : false
            if source == upstream {
                try await repository.pull(remote: nil, branch: nil, strategy: strategy, options: options, progress: nil)
            } else if let target = split(source) {
                try await repository.pull(remote: target.remote, branch: target.branch, strategy: strategy,
                                          options: options, progress: nil)
            }
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
    let repo = MockGitRepository()
    return PullDialogView(repository: repo, refs: RepositoryRefs(repository: repo))
}
