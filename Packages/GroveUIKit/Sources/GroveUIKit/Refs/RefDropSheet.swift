// Refs/RefDropSheet.swift
// GroveUIKit
//
// Confirms a sidebar drop before it runs: merge, rebase, pull or push, with what it will change.

#if os(macOS)
import GroveKit
import SwiftUI

struct RefDropSheet: View {
    @Environment(\.gitStyle) private var style
    let model: GitRefsModel
    let action: GitRefDrop

    /// nil until git says what a plain pull does; the picker waits for it rather than showing Merge first.
    @State private var pullStrategy: PullStrategy?
    @State private var remoteBranchName = ""
    @State private var setUpstream = false

    init(model: GitRefsModel, action: GitRefDrop) {
        self.model = model
        self.action = action
        _pullStrategy = State(initialValue: model.refs.defaultPullStrategy)
    }

    var body: some View {
        GitDialogSheet(title: title, message: message, symbol: symbol, progress: model.isRunningDrop ? progress : nil,
                       errorMessage: model.dropError, primaryTitle: primaryTitle,
                       isPrimaryDisabled: isPushWithoutName || isPullWithoutStrategy,
                       onCancel: model.cancelDrop, onPrimary: confirm) {
            options
        }
        .task {
            if case .push(let branch, let remote) = action {
                remoteBranchName = branch
                // A branch without an upstream starts tracking where it's first pushed.
                let local = model.refs.localBranches.first { $0.name == branch }
                setUpstream = local?.upstream == nil || local?.upstreamRemoteName == remote
            }
            if case .pull = action, pullStrategy == nil { pullStrategy = await model.actions.repository.defaultPullStrategy() }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch action {
        case .merge(let source, let target):
            fields([("Merge", source), ("Into", target)])
        case .rebase(let target, let onto):
            fields([("Rebase", target), ("Onto", onto)])
        case .custom(let drop):
            fields(drop.fields)
        case .pull(let remoteBranch, let target):
            GitDialogCard {
                GitDialogField("From") { mono(remoteBranch) }
                GitDialogField("Into") { mono(target) }
                if isHEAD(target) {
                    GitDialogField("Integrate") {
                        if pullStrategy == nil {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker("Integrate", selection: $pullStrategy) {
                                Text("Merge").tag(PullStrategy?.some(.merge))
                                Text("Rebase").tag(PullStrategy?.some(.rebase))
                                Text("Fast-Forward").tag(PullStrategy?.some(.fastForwardOnly))
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
        case .push(let branch, let remote):
            GitDialogCard {
                GitDialogField("Push") { mono(branch) }
                GitDialogField("To") {
                    HStack(spacing: GitMetrics.Spacing.xs) {
                        Text("\(remote)/").font(style.monoCaption).foregroundStyle(style.textSecondary)
                        TextField(branch, text: $remoteBranchName).textFieldStyle(.roundedBorder).font(style.monoCaption)
                    }
                }
                GitDialogOptionRow(isOn: $setUpstream, label: "Track \(remote)/\(remoteBranchName)",
                                   description: "Sets it as \(branch)'s upstream, so Pull and Push use it.")
            }
        }
    }

    private func fields(_ rows: [(label: String, value: String)]) -> some View {
        GitDialogCard {
            ForEach(rows.indices, id: \.self) { index in
                GitDialogField(rows[index].label) { mono(rows[index].value) }
            }
        }
    }

    private func mono(_ text: String) -> some View {
        Text(text).font(style.monoCaption).lineLimit(1).truncationMode(.middle)
    }

    private func isHEAD(_ branch: String) -> Bool { branch == model.headName }

    private func checkoutNote(_ branch: String) -> String {
        isHEAD(branch) ? "" : " \(branch) is checked out first."
    }

    /// Pulling into HEAD integrates by the strategy, so it waits until the default is known.
    private var isPullWithoutStrategy: Bool {
        if case .pull(_, let target) = action { return isHEAD(target) && pullStrategy == nil }
        return false
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
        case .custom(let drop): drop.title
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
        case .custom(let drop): drop.message
        }
    }

    private var symbol: String {
        switch action {
        case .merge: "arrow.triangle.merge"
        case .rebase: "arrow.triangle.pull"
        case .pull: "arrow.down.to.line"
        case .push: "arrow.up.to.line"
        case .custom(let drop): drop.symbol
        }
    }

    private var primaryTitle: String {
        switch action {
        case .merge: "Merge"
        case .rebase: "Rebase"
        case .pull: "Pull"
        case .push: "Push"
        case .custom(let drop): drop.primaryTitle
        }
    }

    private var progress: String {
        switch action {
        case .merge: "Merging"
        case .rebase: "Rebasing"
        case .pull: "Pulling"
        case .push: "Pushing"
        case .custom(let drop): drop.primaryTitle
        }
    }

    private func confirm() {
        Task { await model.confirmDrop(pullStrategy: pullStrategy ?? .merge, remoteBranchName: remoteBranchName, setUpstream: setUpstream) }
    }
}
#endif
