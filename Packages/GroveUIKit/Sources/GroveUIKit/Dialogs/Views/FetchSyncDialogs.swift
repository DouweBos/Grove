// Dialogs/Views/FetchSyncDialogs.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Downloads new refs from one or all remotes without touching the working tree.
struct FetchDialog: View {
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitFetchForm
    @State private var operation = DialogOperation()

    init(context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitFetchForm(remotes: context.refs.remotes))
    }

    private var remotes: [String] { context.refs.remotes.map(\.name) }
    private var targets: String { form.allRemotes ? remotes.joined(separator: ", ") : form.remote }

    var body: some View {
        GitDialogSheet(
            title: "Fetch",
            message: "Downloads new commits, branches and tags without changing your working copy. Deleted remote branches are pruned.",
            symbol: "arrow.clockwise",
            progress: operation.title, fraction: operation.fraction, errorMessage: operation.errorMessage,
            primaryTitle: "Fetch", isPrimaryDisabled: remotes.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { operation.cancel(); close(false) },
            onPrimary: { operation.submit("Fetching \(targets)", form, context: context, close: close) }
        ) {
            GitDialogCard {
                GitDialogField("Remote") {
                    NamePicker(title: "Remote", names: remotes, selection: $form.remote).disabled(form.allRemotes)
                }
                if remotes.count > 1 {
                    GitDialogOptionRow(isOn: $form.allRemotes, label: "Fetch All Remotes")
                }
            }
        }
    }
}

/// Fetch, pull, then push in one round trip.
struct SyncDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitSyncForm
    @State private var operation = DialogOperation()

    init(context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitSyncForm(branch: context.headBranch, remotes: context.refs.remotes,
                                                strategy: context.refs.defaultPullStrategy))
    }

    private var branch: BranchInfo? { context.headBranch }
    private var branchName: String { branch?.name ?? "HEAD" }
    private var remotes: [String] { context.refs.remotes.map(\.name) }
    private var tracksRemote: Bool { branch?.upstream != nil && branch?.upstreamRemoteName == form.remote }

    private var phase: String {
        switch operation.fraction ?? 0 {
        case ..<0.33: "Fetching"
        case ..<0.66: "Pulling"
        default: "Pushing"
        }
    }

    var body: some View {
        GitDialogSheet(
            title: "Sync",
            message: "Fetches from the remote, integrates new commits into '\(branchName)', then pushes your local commits.",
            symbol: "arrow.triangle.2.circlepath",
            progress: operation.isRunning ? phase : nil, progressDetail: operation.isRunning ? form.remote : "",
            fraction: operation.fraction, errorMessage: operation.errorMessage,
            primaryTitle: "Sync", isPrimaryDisabled: remotes.isEmpty || branch == nil || form.commands.isEmpty,
            blocker: form.unsupportedReason(context.features),
            onCancel: { operation.cancel(); close(false) },
            onPrimary: { operation.submit("Syncing", form, context: context, close: close) }
        ) {
            GitDialogCard {
                GitDialogField("Remote") { NamePicker(title: "Remote", names: remotes, selection: $form.remote) }
                PullStrategyField(strategy: $form.strategy)
            }
            if !tracksRemote {
                GitBanner(symbol: "arrow.up.to.line",
                          message: "'\(branchName)' doesn't track \(form.remote) yet. Sync pushes it to \(form.remote)/\(branchName) and sets that as its upstream.")
            }
        }
        .task { if form.strategy == nil { form.strategy = await context.repository.defaultPullStrategy() } }
    }
}

/// Segmented merge / rebase / fast-forward picker shared by Pull and Sync; a spinner until the default is known.
struct PullStrategyField: View {
    @Environment(\.gitStyle) private var style
    @Binding var strategy: PullStrategy?

    var body: some View {
        GitDialogField("Integrate") {
            if let current = strategy {
                VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
                    Picker("Integrate", selection: Binding(get: { current }, set: { strategy = $0 })) {
                        ForEach(PullStrategy.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .gitClickable()
                    Text(current.summary)
                        .font(style.font(11))
                        .foregroundStyle(style.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif
