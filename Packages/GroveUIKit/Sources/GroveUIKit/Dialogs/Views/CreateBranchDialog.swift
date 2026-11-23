// Dialogs/Views/CreateBranchDialog.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Creates a local branch from a branch, tag or commit.
struct CreateBranchDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitCreateBranchForm
    @State private var commitSubject: String?
    @State private var operation = DialogOperation()

    init(from start: String?, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitCreateBranchForm(start: start ?? context.headBranch?.name ?? "HEAD",
                                                        localBranches: context.refs.localBranches.map(\.name)))
    }

    private var localNames: [String] { context.refs.localBranches.map(\.name) }

    /// Local branches, the preferred one first, plus the requested ref when it isn't one (a tag, SHA or remote branch).
    private var startingPoints: [String] {
        var names = localNames
        if let preferred = context.preferredBranch, let index = names.firstIndex(of: preferred) {
            names.insert(names.remove(at: index), at: 0)
        }
        return names.contains(form.start) ? names : [form.start] + names
    }

    var body: some View {
        GitDialogSheet(
            title: "New Branch",
            message: "Creates a local branch starting at the chosen branch, tag or commit.",
            symbol: "arrow.triangle.branch", width: 440,
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Create Branch", isPrimaryDisabled: !form.isValid, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) }, onPrimary: create
        ) {
            GitDialogCard {
                GitDialogField("Name") {
                    TextField("feature/my-feature", text: $form.name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(create)
                        .gitInitialFocus()
                }
                GitDialogField("Starting At") {
                    Picker("Starting At", selection: $form.start) {
                        ForEach(startingPoints, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .gitClickable()
                }
                GitDialogOptionRow(isOn: $form.track, label: "Track Branch",
                                   description: "The new branch pushes to and pulls from \(label(for: form.start)).")
                if context.pinBranch != nil {
                    GitDialogOptionRow(isOn: $form.pin, label: "Pin Branch",
                                       description: "Adds it to the pinned branches at the top of the sidebar.")
                }
                if context.features.contains(.checkout) {
                    GitDialogOptionRow(isOn: $form.checkout, label: "Check Out Branch",
                                       description: "Checks out the new branch right after creating it.")
                }
            }
            GitDialogOptionsSection {
                GitDialogField("Parent Branch") {
                    VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
                        Picker("Parent Branch", selection: $form.parent) {
                            Text("None").tag("")
                            ForEach(localNames, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .gitClickable()
                        Text("Pull offers the parent as a source, so the new branch can be kept up to date with it.")
                            .font(style.font(11))
                            .foregroundStyle(style.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear { if !context.features.contains(.checkout) { form.checkout = false } }
        .onChange(of: form.start) { old, new in
            // Follow the starting point until the user picks a different parent.
            if form.parent == old || form.parent.isEmpty, localNames.contains(new) { form.parent = new }
        }
        .task(id: form.start) {
            commitSubject = isCommitSHA(form.start) ? try? await context.repository.commitDetail(form.start).summary : nil
        }
    }

    private func isCommitSHA(_ ref: String) -> Bool {
        (7...40).contains(ref.count) && ref.allSatisfy(\.isHexDigit) && !localNames.contains(ref)
    }

    /// "Commit abc1234 · Subject" instead of a raw 40-character SHA.
    private func label(for ref: String) -> String {
        guard isCommitSHA(ref) else { return ref }
        let short = "Commit \(ref.prefix(7))"
        guard ref == form.start, let commitSubject else { return short }
        return "\(short) \u{00B7} \(commitSubject)"
    }

    private func create() {
        guard form.isValid, form.unsupportedReason(context.features) == nil else { return }
        operation.submit("Creating \(form.name.trimmed)", form, context: context, close: close)
    }
}

/// Renames a local branch, or the checked-out one.
struct RenameBranchDialog: View {
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitRenameBranchForm
    @State private var operation = DialogOperation()

    init(branch: String?, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitRenameBranchForm(branch: branch, current: context.headBranch?.name))
    }

    private var title: String { form.original.map { "Rename \($0)" } ?? "Rename Branch" }

    var body: some View {
        GitDialogSheet(
            title: title,
            message: "Only the local branch is renamed; its remote counterpart keeps its name.",
            symbol: "pencil", width: 420,
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Rename", isPrimaryDisabled: form.commands.isEmpty,
            blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) }, onPrimary: rename
        ) {
            GitDialogCard {
                GitDialogField("New Name") {
                    TextField("Branch name", text: $form.name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(rename)
                        .gitInitialFocus()
                }
            }
        }
    }

    private func rename() {
        guard !form.commands.isEmpty, form.unsupportedReason(context.features) == nil else { return }
        operation.submit("Renaming", form, context: context, close: close)
    }
}
#endif
