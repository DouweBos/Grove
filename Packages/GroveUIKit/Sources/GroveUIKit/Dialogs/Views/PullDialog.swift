// Dialogs/Views/PullDialog.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Pulls a remote branch into the checked-out branch: its upstream by default, or another one,
/// which with Rebase is the quick way to rebase onto e.g. `origin/main`.
struct PullDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitPullForm
    @State private var operation = DialogOperation()
    @State private var typingSource = false

    init(context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitPullForm(branch: context.headBranch, remoteBranches: context.refs.remoteBranches,
                                                remotes: context.refs.remotes, strategy: context.refs.defaultPullStrategy))
    }

    private var features: GitFeatures { context.features }
    private var branch: BranchInfo? { context.headBranch }
    private var name: String { branch?.name ?? "HEAD" }
    private var offersOptions: Bool { features.contains(.verifySignatures) || features.contains(.skipHooks) }

    var body: some View {
        GitDialogSheet(
            title: "Pull",
            message: "Fetches a remote branch and integrates it into '\(name)'.",
            symbol: "arrow.down.to.line",
            progress: operation.title, fraction: operation.fraction, errorMessage: operation.errorMessage,
            primaryTitle: "Pull", isPrimaryDisabled: form.commands.isEmpty, blocker: form.unsupportedReason(features),
            onCancel: { operation.cancel(); close(false) },
            onPrimary: {
                operation.submit("Pulling from \(PullSourcePicker.displayName(form.source ?? ""))", form, context: context,
                                 close: close)
            }
        ) {
            GitDialogCard {
                GitDialogField("From") {
                    HStack(spacing: GitMetrics.Spacing.sm) {
                        if typingSource {
                            GitComboBox(text: typedSource, items: sourcePicker.names, placeholder: "remote/branch",
                                        isMonospaced: true)
                                .gitInitialFocus()
                        } else {
                            sourcePicker
                        }
                        if let branch, form.source == form.upstream, branch.behind > 0 {
                            GitStatusBadge(title: "\(branch.behind) behind", symbol: "arrow.down", tone: .caution).fixedSize()
                        }
                    }
                }
                PullStrategyField(strategy: $form.strategy)
                if let outcome {
                    Text(outcome)
                        .font(style.font(12, .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if features.contains(.autostash) {
                    GitDialogOptionRow(isOn: $form.autoStash, label: "Stash Local Changes",
                                       description: "Stashes uncommitted changes first and restores them afterwards.")
                }
            }
            if offersOptions { options }
            if form.upstream == nil { noUpstreamBanner }
        }
        .task { if form.strategy == nil { form.strategy = await context.repository.defaultPullStrategy() } }
        .onChange(of: context.refs.remoteBranches) { _, branches in
            if form.source == nil { form.source = GitPullForm.defaultSource(for: branch, in: branches) }
        }
    }

    private var sourcePicker: PullSourcePicker {
        PullSourcePicker(branches: context.refs.remoteBranches, upstream: form.upstream,
                         parent: branch.flatMap { context.refs.parents[$0.name] },
                         preferred: context.preferredBranch, selection: $form.source,
                         typeOther: { typingSource = true })
    }

    /// A typed `remote/branch`; empty means nothing to pull yet.
    private var typedSource: Binding<String> {
        Binding(get: { form.source ?? "" }, set: { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            form.source = trimmed.isEmpty ? nil : trimmed
        })
    }

    private var options: some View {
        GitDialogOptionsSection {
            if features.contains(.verifySignatures) {
                GitDialogOptionRow(isOn: $form.options.verifySignatures, label: "Verify Signatures",
                                   description: "The pull is aborted if the tip commit of the pulled branch isn't signed with a valid key.")
                    .disabled(form.strategy == .rebase)
            }
            if features.contains(.skipHooks) {
                GitDialogOptionRow(isOn: $form.options.skipHooks, label: "Skip Hooks",
                                   description: "Bypasses the pre-merge-commit and commit-msg hooks.")
                    .disabled(form.strategy == .rebase)
            }
            if form.strategy == .rebase {
                Text("Git ignores these options when rebasing.").font(style.font(11)).foregroundStyle(style.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var noUpstreamBanner: some View {
        let push = branch.map { GitPushForm(branch: $0, isHead: true, remotes: context.refs.remotes) }
        if let push, !context.refs.remotes.isEmpty, push.unsupportedReason(features) == nil {
            GitBanner(symbol: "exclamationmark.triangle",
                      message: "'\(name)' doesn't track a remote branch yet. You can still pull any branch; push it to \(push.remote) to start tracking.",
                      actionTitle: "Push to \(push.remote)",
                      action: { operation.submit("Pushing to \(push.remote)", push, context: context, close: close) })
        } else {
            GitBanner(symbol: "exclamationmark.triangle",
                      message: "'\(name)' doesn't track a remote branch, and there's no remote to push it to.")
        }
    }

    /// Spells out a pull from something other than the upstream, since that changes what the branch becomes.
    private var outcome: String? {
        guard let source = form.source, source != form.upstream, let strategy = form.strategy else { return nil }
        let from = PullSourcePicker.displayName(source)
        switch strategy {
        case .rebase: return "Rebases '\(name)' onto \(from)."
        case .merge: return "Merges \(from) into '\(name)'."
        case .fastForwardOnly: return "Moves '\(name)' forward to \(from), if it hasn't diverged."
        }
    }
}
#endif
