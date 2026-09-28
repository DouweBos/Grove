// Views/Dialogs/PushDialogView.swift
// Grove

import SwiftUI

/// Pushes the checked-out branch to a remote.
struct PushDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let remotes: [RemoteInfo]
    var onComplete: () -> Void = {}

    @State private var selectedRemote: String
    @State private var setUpstream: Bool
    @State private var pushAllTags = false
    @State private var forceWithLease = false
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
        let upstreamRemote = repository.currentBranch?.upstreamRemoteName
        _selectedRemote = State(initialValue: upstreamRemote ?? remotes.first?.name ?? "origin")
        _setUpstream = State(initialValue: repository.currentBranch?.upstream == nil)
    }

    private var branch: BranchInfo? { repository.currentBranch }
    private var branchName: String { branch?.name ?? "HEAD" }
    private var tracksSelectedRemote: Bool { branch?.upstream != nil && branch?.upstreamRemoteName == selectedRemote }

    private var destination: String {
        tracksSelectedRemote && !setUpstream ? (branch?.upstreamShortName ?? "") : "\(selectedRemote)/\(branchName)"
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
            isPrimaryDisabled: remotes.isEmpty || branch == nil,
            onCancel: { dismiss() },
            onPrimary: { forceWithLease ? isConfirmingForce = true : performPush() }
        ) {
            DialogCard {
                DialogField("Remote") {
                    Picker("Remote", selection: $selectedRemote) {
                        ForEach(remotes) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    .disabled(remotes.isEmpty)
                }
                DialogField("Destination") {
                    Text(destination)
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                DialogOptionRow(
                    isOn: $setUpstream,
                    label: "Set Upstream",
                    description: branch?.upstream == nil
                        ? "'\(branchName)' doesn't track a remote branch yet; pull and sync will use \(selectedRemote)/\(branchName)."
                        : "Tracks \(selectedRemote)/\(branchName) instead of \(branch?.upstreamShortName ?? "the current upstream")."
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
            }
        }
        .confirmationDialog("Force push \(branchName) to \(selectedRemote)?", isPresented: $isConfirmingForce) {
            Button("Force Push", role: .destructive, action: performPush)
        } message: {
            Text("Commits on \(destination) that aren't in your branch will be discarded. The push is refused if the remote moved since your last fetch.")
        }
    }

    private func performPush() {
        isPushing = true
        errorMessage = nil
        Task {
            do {
                try await repository.push(remote: selectedRemote, forceWithLease: forceWithLease,
                                          setUpstream: setUpstream, progress: nil)
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
