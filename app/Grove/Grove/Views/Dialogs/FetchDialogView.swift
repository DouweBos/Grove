// Views/Dialogs/FetchDialogView.swift
// Grove
//
// Fetch dialog: remote picker, prune option, Cancel + "Fetch" button.

import SwiftUI

// MARK: - FetchDialogView

/// Dialog for fetching from a remote.
struct FetchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let remotes: [RemoteInfo]

    @State private var selectedRemote: String
    @State private var pruneDeletedBranches = true
    @State private var fetchAllRemotes = false
    @State private var isFetching = false
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, remotes: [RemoteInfo] = []) {
        self.repository = repository
        self.remotes = remotes
        _selectedRemote = State(initialValue: remotes.first?.name ?? "origin")
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Fetch",
                description: "Downloads new data from the remote repository without integrating it into your working files."
            )

            Divider()

            Form {
                LabeledContent("Remote") {
                    Picker("", selection: $selectedRemote) {
                        ForEach(remoteNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(fetchAllRemotes)
                }

                Toggle("Fetch All Remotes", isOn: $fetchAllRemotes)
            }
            .formStyle(.grouped)

            DialogOptionsSection {
                DialogOptionRow(
                    isOn: $pruneDeletedBranches,
                    label: "Prune Deleted Branches",
                    description: "Remove remote-tracking references that no longer exist on the remote."
                )
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Divider()

            SheetFooter(
                cancelAction: { dismiss() },
                primaryLabel: isFetching ? "Fetching\u{2026}" : "Fetch",
                primaryAction: performFetch,
                isPrimaryDisabled: isFetching
            )
        }
        .frame(width: 460)
    }

    private var remoteNames: [String] {
        guard !remotes.isEmpty else { return [selectedRemote] }
        return remotes.map(\.name)
    }

    private func performFetch() {
        isFetching = true
        errorMessage = nil
        Task {
            do {
                let remote = fetchAllRemotes ? nil : selectedRemote
                try await repository.fetch(remote: remote, progress: nil)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isFetching = false
            }
        }
    }
}

#Preview {
    FetchDialogView(
        repository: MockGitRepository(),
        remotes: MockData.remotes
    )
}
