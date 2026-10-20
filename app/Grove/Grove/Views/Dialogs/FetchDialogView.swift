// Views/Dialogs/FetchDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Downloads new refs from one or all remotes without touching the working tree.
struct FetchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let remotes: [RemoteInfo]
    var onComplete: () -> Void = {}

    @State private var selectedRemote: String
    @State private var fetchAllRemotes = false
    @State private var operation = DialogOperation()
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
            progress: operation.isRunning ? "Fetching \(targets.joined(separator: ", "))…" : nil,
            fraction: operation.isRunning ? operation.fraction : nil,
            errorMessage: errorMessage,
            primaryTitle: "Fetch",
            isPrimaryDisabled: remotes.isEmpty,
            onCancel: cancel,
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
        errorMessage = nil
        let targets = targets
        operation.run({ progress in
            for (index, remote) in targets.enumerated() {
                try await repository.fetch(remote: remote) { progress((Double(index) + $0) / Double(targets.count)) }
            }
        }, completion: { result in
            switch result {
            case .success: onComplete(); dismiss()
            case .failure(let error): errorMessage = error.localizedDescription
            case nil: onComplete()
            }
        })
    }

    /// Stops a running fetch too; git leaves the refs it already updated.
    private func cancel() {
        operation.cancel()
        dismiss()
    }
}

#Preview {
    FetchDialogView(repository: MockGitRepository(), remotes: MockData.remotes)
}
