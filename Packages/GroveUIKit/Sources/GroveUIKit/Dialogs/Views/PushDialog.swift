// Dialogs/Views/PushDialog.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Pushes a local branch, the checked-out one by default, to a branch on a remote: its upstream by default.
struct PushDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    private let branch: BranchInfo?
    @State private var form: GitPushForm?
    @State private var submoduleMode = SubmodulePushMode.check
    @State private var isConfirmingForce = false
    @State private var operation = DialogOperation()

    init(name: String?, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        let head = context.headBranch
        let branch = name.flatMap { name in context.refs.localBranches.first { $0.name == name } } ?? (name == nil ? head : nil)
        self.branch = branch
        _form = State(initialValue: branch.map {
            GitPushForm(branch: $0, isHead: $0.name == head?.name, remotes: context.refs.remotes)
        })
    }

    private var features: GitFeatures { context.features }
    private var remotes: [String] { context.refs.remotes.map(\.name) }
    private var branchName: String { branch?.name ?? "HEAD" }

    /// A branch without an upstream is published; the ahead count is only known relative to the upstream.
    private var title: String {
        guard let form, form.upstream != nil else { return "Publish \(branchName)" }
        if let ahead = branch?.ahead, ahead > 0, form.upstream == form.destination {
            return "Push \(ahead) commit\(ahead == 1 ? "" : "s") to \(form.target.trimmed)"
        }
        return "Push \(branchName) to \(form.target.trimmed.isEmpty ? form.remote : form.target.trimmed)"
    }

    private var upstreamDescription: String {
        guard let form, let upstream = form.upstream else {
            return "'\(branchName)' doesn't track a remote branch yet; pull and sync will use \(form?.destination ?? "it")."
        }
        return upstream == form.destination ? "Already tracks \(upstream)." : "Tracks \(form.destination) instead of \(upstream)."
    }

    var body: some View {
        GitDialogSheet(
            title: title,
            message: "Sends the commits on your local branch '\(branchName)' to the remote.",
            symbol: "arrow.up.to.line",
            progress: operation.title, fraction: operation.fraction, errorMessage: operation.errorMessage,
            primaryTitle: form?.forceWithLease == true ? "Force Push" : form?.upstream == nil ? "Publish" : "Push",
            isDestructive: form?.forceWithLease == true,
            isPrimaryDisabled: remotes.isEmpty || form?.commands.isEmpty != false,
            blocker: branch == nil ? "Check out a branch first." : form?.unsupportedReason(features),
            onCancel: { operation.cancel(); close(false) },
            onPrimary: { form?.forceWithLease == true ? isConfirmingForce = true : push() }
        ) {
            if let form = Binding($form) {
                fields(form)
                options(form)
            }
        }
        .onChange(of: form?.remote) { old, new in
            // Only follow the remote while the branch name is still the untouched default.
            guard let branch, let old, let new, form?.target == GitPushForm.defaultTarget(for: branch, on: old) else { return }
            form?.target = GitPushForm.defaultTarget(for: branch, on: new)
        }
        .confirmationDialog("Force push \(branchName) to \(form?.destination ?? "")?", isPresented: $isConfirmingForce) {
            Button("Force Push", role: .destructive, action: push)
        } message: {
            Text("Commits on \(form?.destination ?? "the remote") that aren't in your branch will be discarded. The push is refused if the remote moved since your last fetch.")
        }
    }

    private func fields(_ form: Binding<GitPushForm>) -> some View {
        GitDialogCard {
            if remotes.count > 1 {
                GitDialogField("Remote") { NamePicker(title: "Remote", names: remotes, selection: form.remote) }
            }
            GitDialogField("To Branch") {
                HStack(spacing: GitMetrics.Spacing.xs) {
                    Text("\(form.wrappedValue.remote)/").font(style.monoCaption).foregroundStyle(style.textSecondary)
                    GitComboBox(text: form.target, items: existingTargets(on: form.wrappedValue.remote),
                                placeholder: "Branch name", isMonospaced: true)
                        .gitInitialFocus()
                }
            }
            GitDialogOptionRow(isOn: form.setUpstream, label: "Set Upstream", description: upstreamDescription)
        }
    }

    private func options(_ form: Binding<GitPushForm>) -> some View {
        GitDialogOptionsSection(isExpanded: form.wrappedValue.forceWithLease) {
            GitDialogField("Tags") {
                Picker("Tags", selection: form.tags) {
                    Text("None").tag(PushTags.none)
                    Text("Annotated Tags on Pushed Commits").tag(PushTags.follow)
                    Text("All Tags").tag(PushTags.all)
                }
                .labelsHidden()
                .fixedSize()
                .gitClickable()
            }
            GitDialogOptionRow(isOn: form.forceWithLease, label: "Force Push (with Lease)",
                               description: "Overwrites the remote branch, unless someone else pushed to it since your last fetch.")
            if features.contains(.recurseSubmodules) {
                GitDialogOptionRow(isOn: recurseSubmodules(form), label: "Recurse Submodules",
                                   description: "Makes sure the submodule commits this branch references are on their remotes.")
                Picker("Submodules", selection: $submoduleMode) {
                    ForEach(SubmodulePushMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .padding(.leading, 20 * style.fontScale)
                .disabled(form.wrappedValue.recurseSubmodules == nil)
                .gitClickable()
                .onChange(of: submoduleMode) { _, mode in
                    if form.wrappedValue.recurseSubmodules != nil { form.wrappedValue.recurseSubmodules = mode }
                }
            }
            if features.contains(.skipHooks) {
                GitDialogOptionRow(isOn: form.skipHooks, label: "Skip Hooks", description: "Bypasses the pre-push hook.")
            }
        }
    }

    private func recurseSubmodules(_ form: Binding<GitPushForm>) -> Binding<Bool> {
        Binding(get: { form.wrappedValue.recurseSubmodules != nil },
                set: { form.wrappedValue.recurseSubmodules = $0 ? submoduleMode : nil })
    }

    /// Branch names already on the remote, offered next to the free-form field.
    private func existingTargets(on remote: String) -> [String] {
        context.refs.remoteBranches.filter { $0.remoteName == remote && !$0.name.hasSuffix("/HEAD") }
            .map { String($0.name.dropFirst(remote.count + 1)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func push() {
        guard let form else { return }
        operation.submit("Pushing to \(form.remote)", form, context: context, close: close)
    }
}
#endif
