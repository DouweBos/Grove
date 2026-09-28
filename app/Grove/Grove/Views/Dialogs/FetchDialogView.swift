// Views/Dialogs/FetchDialogView.swift
// Grove

import SwiftUI

/// Downloads new refs from one or all remotes without touching the working tree.
struct FetchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let remotes: [RemoteInfo]
    var onComplete: () -> Void = {}

    @State private var selectedRemote: String
    @State private var fetchAllRemotes = false
    @State private var isFetching = false
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, remotes: [RemoteInfo] = [], onComplete: @escaping () -> Void = {}) {
        self.repository = repository
        self.remotes = remotes
        self.onComplete = onComplete
        _selectedRemote = State(initialValue: remotes.first?.name ?? "origin")
        _fetchAllRemotes = State(initialValue: remotes.count > 1)
    }

    private var targets: [String] { fetchAllRemotes ? remotes.map(\.name) : [selectedRemote] }

    var body: some View {
        DialogSheet(
            title: "Fetch",
            message: "Downloads new commits, branches and tags without changing your working copy. Deleted remote branches are pruned.",
            symbol: "arrow.clockwise",
            progress: isFetching ? "Fetching \(targets.joined(separator: ", "))…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Fetch",
            isPrimaryDisabled: remotes.isEmpty,
            onCancel: { dismiss() },
            onPrimary: performFetch
        ) {
            DialogCard {
                DialogField("Remote") {
                    Picker("Remote", selection: $selectedRemote) {
                        ForEach(remotes) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    .disabled(fetchAllRemotes || remotes.isEmpty)
                }
                if remotes.count > 1 {
                    DialogOptionRow(isOn: $fetchAllRemotes, label: "Fetch All Remotes")
                }
            }
        }
    }

    private func performFetch() {
        isFetching = true
        errorMessage = nil
        let targets = targets
        Task {
            do {
                for remote in targets {
                    try await repository.fetch(remote: remote, progress: nil)
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isFetching = false
            }
        }
    }
}

#Preview {
    FetchDialogView(repository: MockGitRepository(), remotes: MockData.remotes)
}
