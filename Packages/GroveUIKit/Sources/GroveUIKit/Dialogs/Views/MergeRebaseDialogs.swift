// Dialogs/Views/MergeRebaseDialogs.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Merges a chosen branch into the checked-out branch.
struct MergeDialog: View {
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitMergeForm
    @State private var operation = DialogOperation()

    init(context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitMergeForm(candidates: context.otherLocalBranches))
    }

    private var head: String { context.headBranch?.name ?? "HEAD" }

    var body: some View {
        GitDialogSheet(
            title: "Merge into \(head)",
            message: "Brings the commits of the chosen branch into '\(head)'. Conflicts are left for you to resolve.",
            symbol: "arrow.triangle.merge",
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Merge", isPrimaryDisabled: form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) },
            onPrimary: { operation.submit("Merging \(form.branch)", form, context: context, close: close) }
        ) {
            GitDialogCard {
                GitDialogField("Branch") { NamePicker(title: "Branch", names: context.otherLocalBranches, selection: $form.branch) }
                GitDialogOptionRow(isOn: $form.squash, label: "Squash into One Commit",
                                   description: "Stages the branch's changes for you to commit, instead of a merge commit.")
            }
        }
        // Opened before the refs first loaded: pick a branch once they arrive.
        .onChange(of: context.otherLocalBranches) { _, names in
            if form.branch.isEmpty, let first = names.first { form.branch = first }
        }
    }
}

/// Rebases the checked-out branch onto another branch.
struct RebaseDialog: View {
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitRebaseForm
    @State private var operation = DialogOperation()

    init(context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitRebaseForm(candidates: context.otherLocalBranches))
    }

    private var head: String { context.headBranch?.name ?? "HEAD" }

    var body: some View {
        GitDialogSheet(
            title: "Rebase \(head)",
            message: "Replays the commits of '\(head)' on top of the chosen branch, rewriting their history.",
            symbol: "arrow.triangle.pull",
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Rebase", isPrimaryDisabled: form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) },
            onPrimary: { operation.submit("Rebasing onto \(form.onto)", form, context: context, close: close) }
        ) {
            GitDialogCard {
                GitDialogField("Onto") { NamePicker(title: "Onto", names: context.otherLocalBranches, selection: $form.onto) }
                if context.features.contains(.autostash) {
                    GitDialogOptionRow(isOn: $form.autoStash, label: "Stash Local Changes",
                                       description: "Stashes uncommitted changes first and restores them afterwards.")
                }
            }
        }
        .onChange(of: context.otherLocalBranches) { _, names in
            if form.onto.isEmpty, let first = names.first { form.onto = first }
        }
    }
}
#endif
