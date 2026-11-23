// Dialogs/Views/SnapshotTagDialogs.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Saves the working state as a stash while leaving every change in place.
struct SnapshotDialog: View {
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitSnapshotForm
    @State private var operation = DialogOperation()

    init(context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitSnapshotForm(branch: context.headBranch?.name))
    }

    var body: some View {
        GitDialogSheet(
            title: "Save Snapshot",
            message: "Keeps a copy of your uncommitted changes in the stash list. Your working copy isn't touched.",
            symbol: "camera.aperture",
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Save Snapshot", isPrimaryDisabled: form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) }, onPrimary: save
        ) {
            GitDialogCard {
                GitDialogField("Message") {
                    TextField("Snapshot message", text: $form.message)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                        .gitInitialFocus()
                }
                GitDialogOptionRow(isOn: $form.includeUntracked, label: "Include Untracked Files")
            }
        }
    }

    private func save() {
        guard !form.commands.isEmpty else { return }
        operation.submit("Saving", form, context: context, close: close)
    }
}

/// Creates a lightweight or annotated tag at HEAD or another commit.
struct TagDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitTagForm
    @State private var operation = DialogOperation()

    init(target: String?, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitTagForm(target: target))
    }

    private var message: String {
        let target = form.target.trimmed
        let isCommit = (7...40).contains(target.count) && target.allSatisfy(\.isHexDigit)
        return "Marks \(target.isEmpty || target == "HEAD" ? "the current HEAD commit" : isCommit ? "commit \(target.prefix(7))" : target) with a name, e.g. a release."
    }

    var body: some View {
        GitDialogSheet(
            title: "New Tag", message: message, symbol: "tag", width: 440,
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Create Tag", isPrimaryDisabled: form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) }, onPrimary: create
        ) {
            GitDialogCard {
                GitDialogField("Name") {
                    TextField("v1.0.0", text: $form.name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(create)
                        .gitInitialFocus()
                }
                GitDialogField("At") {
                    TextField("HEAD", text: $form.target).textFieldStyle(.roundedBorder).font(style.monoCaption)
                }
                GitDialogOptionRow(isOn: $form.annotated, label: "Annotated",
                                   description: "Stores a message, author and date with the tag.")
                if form.annotated {
                    GitDialogField("Message") {
                        TextEditor(text: $form.message)
                            .font(style.font(13))
                            .scrollContentBackground(.hidden)
                            .padding(GitMetrics.Spacing.xs)
                            .frame(height: 72 * style.fontScale)
                            .background(style.background, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile))
                            .overlay(RoundedRectangle(cornerRadius: GitMetrics.Radius.tile).strokeBorder(style.border, lineWidth: 0.5))
                            .accessibilityLabel("Tag message")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: form.annotated)
        }
    }

    private func create() {
        guard !form.commands.isEmpty, form.unsupportedReason(context.features) == nil else { return }
        operation.submit("Creating \(form.name.trimmed)", form, context: context, close: close)
    }
}
#endif
