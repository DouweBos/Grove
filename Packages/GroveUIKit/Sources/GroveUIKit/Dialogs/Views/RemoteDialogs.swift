// Dialogs/Views/RemoteDialogs.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Adds a named remote, or renames one and changes its URL.
struct RemoteDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitRemoteForm
    @State private var operation = DialogOperation()

    init(remote: RemoteInfo?, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitRemoteForm(remote: remote, existing: context.refs.remotes))
    }

    private var isAdding: Bool { form.original == nil }
    private var problem: String? { form.nameProblem(existing: context.refs.remotes) }

    var body: some View {
        GitDialogSheet(
            title: form.original.map { "Edit \($0.name)" } ?? "Add Remote",
            message: isAdding
                ? "Connects this repository to another copy of it, such as one on GitHub."
                : "Renames the remote or points it at another URL. Its remote branches follow a new name.",
            symbol: "cloud",
            progress: operation.title,
            // Only once something is typed, so an empty field doesn't open with an error.
            errorMessage: operation.errorMessage ?? (form.name.isEmpty ? nil : problem),
            primaryTitle: isAdding ? "Add Remote" : "Save",
            isPrimaryDisabled: problem != nil || form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) }, onPrimary: save
        ) {
            GitDialogCard {
                GitDialogField("Name") {
                    TextField("origin", text: $form.name).textFieldStyle(.roundedBorder).font(style.monoCaption).gitInitialFocus()
                }
                GitDialogField("URL") {
                    TextField("https://github.com/owner/repository.git", text: $form.url)
                        .textFieldStyle(.roundedBorder).font(style.monoCaption).onSubmit(save)
                }
            }
        }
        .onChange(of: form.name) { operation.errorMessage = nil }
        .onChange(of: form.url) { operation.errorMessage = nil }
    }

    private func save() {
        guard problem == nil, !form.commands.isEmpty, form.unsupportedReason(context.features) == nil else { return }
        let name = form.name.trimmed
        operation.submit(isAdding ? "Adding \(name)" : "Saving \(name)", form, context: context) { submitted in
            close(submitted)
            if submitted, isAdding { context.onRemoteAdded?(name) }
        }
    }
}

/// Makes a branch at a stash's commit with the stash applied, and drops it.
struct StashBranchDialog: View {
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitStashBranchForm
    @State private var operation = DialogOperation()

    init(index: Int, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitStashBranchForm(index: index))
    }

    var body: some View {
        GitDialogSheet(
            title: "New Branch from stash@{\(form.index)}",
            message: "Creates a branch at the commit the stash was made on, checks it out and applies the stash. The stash is dropped if it applies cleanly.",
            symbol: "arrow.triangle.branch", width: 440,
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Create Branch", isPrimaryDisabled: form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) }, onPrimary: create
        ) {
            GitDialogCard {
                GitDialogField("Name") {
                    TextField("Branch name", text: $form.name).textFieldStyle(.roundedBorder).onSubmit(create).gitInitialFocus()
                }
            }
        }
    }

    private func create() {
        guard !form.commands.isEmpty else { return }
        operation.submit("Creating \(form.name.trimmed)", form, context: context, close: close)
    }
}
#endif
