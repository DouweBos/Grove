// Views/Sidebar/SidebarDropSheet.swift
// Grove
//
// Confirms a sidebar drop before it runs: merge, rebase, pull or push, with what it will change.

import SwiftUI

struct SidebarDropSheet: View {
    let viewModel: SidebarViewModel
    let action: SidebarDropAction

    @State private var pullStrategy = PullStrategy.merge
    @State private var remoteBranchName = ""
    @State private var setUpstream = false

    var body: some View {
        DialogSheet(
            title: title,
            message: message,
            symbol: symbol,
            progress: viewModel.isRunningDrop ? progress : nil,
            errorMessage: viewModel.dropError,
            primaryTitle: primaryTitle,
            isPrimaryDisabled: isPushWithoutName,
            onCancel: viewModel.cancelDrop,
            onPrimary: confirm
        ) {
            options
        }
        .task {
            if case .push(let branch, let remote) = action {
                remoteBranchName = branch
                // A branch without an upstream starts tracking where it's first pushed.
                let local = viewModel.localBranches.first { $0.name == branch }
                setUpstream = local?.upstream == nil || local?.upstreamRemoteName == remote
            }
            if case .pull = action { pullStrategy = await viewModel.repository.defaultPullStrategy() }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var options: some View {
        switch action {
        case .merge(let source, let target):
            DialogCard {
                DialogField("Merge") { mono(source) }
                DialogField("Into") { mono(target) }
            }
        case .rebase(let target, let onto):
            DialogCard {
                DialogField("Rebase") { mono(target) }
                DialogField("Onto") { mono(onto) }
            }
        case .pull(let remoteBranch, let target):
            DialogCard {
                DialogField("From") { mono(remoteBranch) }
                DialogField("Into") { mono(target) }
                if isHEAD(target) {
                    DialogField("Integrate") {
                        Picker("Integrate", selection: $pullStrategy) {
                            Text("Merge").tag(PullStrategy.merge)
                            Text("Rebase").tag(PullStrategy.rebase)
                            Text("Fast-Forward").tag(PullStrategy.fastForwardOnly)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        case .push(let branch, let remote):
            DialogCard {
                DialogField("Push") { mono(branch) }
                DialogField("To") {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("\(remote)/").font(.monoCaption).foregroundStyle(Theme.textSecondary)
                        TextField(branch, text: $remoteBranchName).textFieldStyle(.roundedBorder).font(.monoCaption)
                    }
                }
                DialogOptionRow(isOn: $setUpstream, label: "Track \(remote)/\(remoteBranchName)",
                                description: "Sets it as \(branch)'s upstream, so Pull and Push use it.")
            }
        }
    }

    private func mono(_ text: String) -> some View {
        Text(text).font(.monoCaption).lineLimit(1).truncationMode(.middle)
    }

    // MARK: Copy

    private func isHEAD(_ branch: String) -> Bool { branch == viewModel.headName }

    private func checkoutNote(_ branch: String) -> String {
        isHEAD(branch) ? "" : " \(branch) is checked out first."
    }

    private var isPushWithoutName: Bool {
        if case .push = action { return remoteBranchName.trimmingCharacters(in: .whitespaces).isEmpty }
        return false
    }

    private var title: String {
        switch action {
        case .merge(let source, let target): "Merge \(source) into \(target)?"
        case .rebase(let target, let onto): "Rebase \(target) onto \(onto)?"
        case .pull(let remoteBranch, let target): "Pull \(remoteBranch) into \(target)?"
        case .push(let branch, let remote): "Push \(branch) to \(remote)?"
        }
    }

    private var message: String {
        switch action {
        case .merge(let source, let target):
            "Brings the commits of \(source) into \(target).\(checkoutNote(target)) Conflicts are left for you to resolve."
        case .rebase(let target, let onto):
            "Replays \(target)'s own commits on top of \(onto), rewriting them.\(checkoutNote(target)) "
                + "Don't rebase commits others already pulled."
        case .pull(let remoteBranch, let target):
            isHEAD(target)
                ? "Fetches \(remoteBranch) and integrates it into the checked-out \(target)."
                : "Fetches \(remoteBranch) and moves \(target) to it. Only a fast-forward: if \(target) has commits of its own, "
                    + "nothing changes and you'll need to check it out and pull."
        case .push(let branch, let remote):
            "Uploads \(branch)'s commits to \(remote). It fails rather than overwrite commits on the remote you don't have."
        }
    }

    private var symbol: String {
        switch action {
        case .merge: "arrow.triangle.merge"
        case .rebase: "arrow.triangle.pull"
        case .pull: "arrow.down.to.line"
        case .push: "arrow.up.to.line"
        }
    }

    private var primaryTitle: String {
        switch action {
        case .merge: "Merge"
        case .rebase: "Rebase"
        case .pull: "Pull"
        case .push: "Push"
        }
    }

    private var progress: String {
        switch action {
        case .merge: "Merging…"
        case .rebase: "Rebasing…"
        case .pull: "Pulling…"
        case .push: "Pushing…"
        }
    }

    private func confirm() {
        Task { await viewModel.confirmDrop(pullStrategy: pullStrategy, remoteBranchName: remoteBranchName, setUpstream: setUpstream) }
    }
}

#Preview {
    SidebarDropSheet(viewModel: SidebarViewModel(repository: MockGitRepository()),
                     action: .merge(source: "feature/login", target: "main"))
}
