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
    @State private var pushAllTags = false
    @State private var forceWithLease = false
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
    }

    private var branchName: String { repository.currentBranch?.name ?? "HEAD" }

    var body: some View {
        DialogSheet(
            title: "Push \(branchName)",
            message: "Sends the commits on your local branch '\(branchName)' to the remote.",
            symbol: "arrow.up.to.line",
            progress: isPushing ? "Pushing to \(selectedRemote)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Push",
            isPrimaryDisabled: remotes.isEmpty,
            onCancel: { dismiss() },
            onPrimary: performPush
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
                    Text("\(selectedRemote)/\(branchName)")
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            DialogOptionsSection {
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
    }

    private func performPush() {
        isPushing = true
        errorMessage = nil
        Task {
            do {
                try await repository.push(remote: selectedRemote, force: false, forceWithLease: forceWithLease, progress: nil)
                if pushAllTags {
                    try await repository.pushAllTags(remote: selectedRemote)
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isPushing = false
            }
        }
    }
}

#Preview {
    PushDialogView(repository: MockGitRepository(), remotes: MockData.remotes)
}
