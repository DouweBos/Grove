// Views/Dialogs/SyncDialogView.swift
// Grove
//
// Sync dialog: performs fetch + pull + push in sequence.
// Shows per-phase progress and a rebase toggle matching the pull dialog style.

import SwiftUI

// MARK: - SyncDialogView

/// Dialog that runs fetch, pull, then push in a single "sync" round-trip.
///
/// Modelled after ``PullDialogView``: remote picker, rebase toggle, progress
/// bar that advances through the three phases.
struct SyncDialogView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: Dependencies

    let repository: any GitRepositoryProtocol
    let remotes: [RemoteInfo]

    // MARK: State

    @State private var selectedRemote: String
    @State private var useRebase = false
    @State private var isSyncing = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    // MARK: Init

    init(
        repository: any GitRepositoryProtocol,
        remotes: [RemoteInfo] = []
    ) {
        self.repository = repository
        self.remotes = remotes
        _selectedRemote = State(initialValue: remotes.first?.name ?? "origin")
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Sync",
                description: "Fetches from the remote, integrates changes into the local HEAD branch, then pushes local commits back."
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
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Use Rebase Instead of Merge", isOn: $useRebase)
                        .fontWeight(.medium)
                    Text("Rebases the local HEAD branch onto the fetched revisions during pull.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.vertical, 4)
            }
            .formStyle(.grouped)

            if isSyncing {
                ProgressView(value: progress)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
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
                primaryLabel: isSyncing ? "Syncing\u{2026}" : "Sync",
                primaryAction: performSync,
                isPrimaryDisabled: isSyncing
            )
        }
        .frame(width: 460)
    }

    // MARK: Helpers

    private var remoteNames: [String] {
        guard !remotes.isEmpty else { return [selectedRemote] }
        return remotes.map(\.name)
    }

    private func performSync() {
        isSyncing = true
        errorMessage = nil
        progress = 0
        Task {
            do {
                let remote: String? = selectedRemote.isEmpty ? nil : selectedRemote
                try await repository.sync(
                    remote: remote,
                    rebase: useRebase,
                    progress: { value in
                        Task { @MainActor in progress = value }
                    }
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSyncing = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SyncDialogView(
        repository: MockGitRepository(),
        remotes: MockData.remotes
    )
}
