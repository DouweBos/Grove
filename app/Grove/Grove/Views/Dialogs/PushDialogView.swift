// Views/Dialogs/PushDialogView.swift
// Grove

import SwiftUI

/// Pushes the checked-out branch to a branch on a remote, its upstream by default.
struct PushDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let remotes: [RemoteInfo]
    var onComplete: () -> Void = {}

    @State private var selectedRemote: String
    @State private var targetBranch: String
    @State private var remoteBranches: [BranchInfo] = []
    @State private var setUpstream: Bool
    @State private var pushAllTags = false
    @State private var forceWithLease = false
    @State private var options = PushOptions()
    @State private var submoduleMode = SubmodulePushMode.check
    @State private var isConfirmingForce = false
    @State private var isPushing = false
    @State private var errorMessage: String?

    init(
        repository: any GitRepositoryProtocol,
        remotes: [RemoteInfo] = [],
        onComplete: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.remotes = remotes
        self.onComplete = onComplete
        let remote = repository.currentBranch?.upstreamRemoteName ?? remotes.first?.name ?? "origin"
        _selectedRemote = State(initialValue: remote)
        _targetBranch = State(initialValue: Self.defaultTarget(for: repository.currentBranch, on: remote))
        _setUpstream = State(initialValue: repository.currentBranch?.upstream == nil)
    }

    private var branch: BranchInfo? { repository.currentBranch }
    private var branchName: String { branch?.name ?? "HEAD" }
    private var trimmedTarget: String { targetBranch.trimmingCharacters(in: .whitespaces) }
    private var destination: String { "\(selectedRemote)/\(trimmedTarget)" }

    private var upstreamDescription: String {
        guard let upstream = branch?.upstreamShortName else {
            return "'\(branchName)' doesn't track a remote branch yet; pull and sync will use \(destination)."
        }
        return upstream == destination ? "Already tracks \(upstream)." : "Tracks \(destination) instead of \(upstream)."
    }

    /// Branch names already on the selected remote, offered next to the free-form field.
    private var existingTargets: [String] {
        remoteBranches.filter { $0.remoteName == selectedRemote }
            .map { String($0.name.dropFirst(selectedRemote.count + 1)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The upstream's branch name when it lives on `remote`, else the local branch's name.
    private static func defaultTarget(for branch: BranchInfo?, on remote: String) -> String {
        if let upstream = branch?.upstreamShortName, branch?.upstreamRemoteName == remote {
            return String(upstream.dropFirst(remote.count + 1))
        }
        return branch?.name ?? ""
    }

    var body: some View {
        DialogSheet(
            title: "Push \(branchName)",
            message: "Sends the commits on your local branch '\(branchName)' to the remote.",
            symbol: "arrow.up.to.line",
            progress: isPushing ? "Pushing to \(selectedRemote)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: forceWithLease ? "Force Push…" : "Push",
            isDestructive: forceWithLease,
            isPrimaryDisabled: remotes.isEmpty || branch == nil || trimmedTarget.isEmpty,
            onCancel: { dismiss() },
            onPrimary: { forceWithLease ? isConfirmingForce = true : performPush() }
        ) {
            DialogCard {
                if remotes.count > 1 {
                    DialogField("Remote") {
                        Picker("Remote", selection: $selectedRemote) {
                            ForEach(remotes) { Text($0.name).tag($0.name) }
                        }
                        .labelsHidden()
                    }
                }
                DialogField("To Branch") {
                    targetField
                }
                DialogOptionRow(
                    isOn: $setUpstream,
                    label: "Set Upstream",
                    description: upstreamDescription
                )
            }
            DialogOptionsSection(isExpanded: forceWithLease) {
                DialogOptionRow(
                    isOn: $pushAllTags,
                    label: "Push All Tags",
                    description: "Also sends every tag under refs/tags."
                )
                DialogOptionRow(
                    isOn: $forceWithLease,
                    label: "Force Push (with Lease)",
                    description: "Overwrites the remote branch, unless someone else pushed to it since your last fetch."
                )
                DialogOptionRow(
                    isOn: recurseSubmodules,
                    label: "Recurse Submodules",
                    description: "Makes sure the submodule commits this branch references are on their remotes."
                )
                Picker("Submodules", selection: $submoduleMode) {
                    ForEach(SubmodulePushMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .padding(.leading, 20)
                .disabled(options.recurseSubmodules == nil)
                .onChange(of: submoduleMode) { _, mode in
                    if options.recurseSubmodules != nil { options.recurseSubmodules = mode }
                }
                DialogOptionRow(
                    isOn: $options.skipHooks,
                    label: "Skip Hooks",
                    description: "Bypasses the pre-push hook."
                )
            }
        }
        .task {
            remoteBranches = (try? await repository.remoteBranches()) ?? []
        }
        .onChange(of: selectedRemote) { oldRemote, newRemote in
            // Only follow the remote while the branch name is still the untouched default.
            if targetBranch == Self.defaultTarget(for: branch, on: oldRemote) {
                targetBranch = Self.defaultTarget(for: branch, on: newRemote)
            }
        }
        .confirmationDialog("Force push \(branchName) to \(destination)?", isPresented: $isConfirmingForce) {
            Button("Force Push", role: .destructive, action: performPush)
        } message: {
            Text("Commits on \(destination) that aren't in your branch will be discarded. The push is refused if the remote moved since your last fetch.")
        }
    }

    private var recurseSubmodules: Binding<Bool> {
        Binding(get: { options.recurseSubmodules != nil },
                set: { options.recurseSubmodules = $0 ? submoduleMode : nil })
    }

    private var targetField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("\(selectedRemote)/")
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            ComboBox(text: $targetBranch, items: existingTargets, placeholder: "Branch name", isMonospaced: true)
        }
    }

    private func performPush() {
        isPushing = true
        errorMessage = nil
        Task {
            do {
                try await repository.push(remote: selectedRemote, branch: trimmedTarget, forceWithLease: forceWithLease,
                                          setUpstream: setUpstream, options: options, progress: nil)
                if pushAllTags {
                    try await repository.pushAllTags(remote: selectedRemote)
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isPushing = false
                onComplete()
            }
        }
    }
}

#Preview {
    PushDialogView(repository: MockGitRepository(), remotes: MockData.remotes)
}
