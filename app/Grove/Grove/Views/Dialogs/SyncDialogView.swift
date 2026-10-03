// Views/Dialogs/SyncDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Fetch, pull, then push in one round-trip.
struct SyncDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let remotes: [RemoteInfo]
    var onComplete: () -> Void = {}

    @State private var selectedRemote: String
    @State private var strategy: PullStrategy = .merge
    @State private var isSyncing = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, remotes: [RemoteInfo] = [], onComplete: @escaping () -> Void = {}) {
        self.repository = repository
        self.remotes = remotes
        self.onComplete = onComplete
        let upstreamRemote = repository.currentBranch?.upstreamRemoteName
        _selectedRemote = State(initialValue: upstreamRemote ?? remotes.first?.name ?? "origin")
    }

    private var phase: String {
        switch progress {
        case ..<0.33: "Fetching…"
        case ..<0.66: "Pulling…"
        default: "Pushing…"
        }
    }

    var body: some View {
        DialogSheet(
            title: "Sync",
            message: "Fetches from the remote, integrates new commits into '\(repository.currentBranch?.name ?? "HEAD")', then pushes your local commits.",
            symbol: "arrow.triangle.2.circlepath",
            progress: isSyncing ? phase : nil,
            progressDetail: isSyncing ? selectedRemote : "",
            fraction: isSyncing ? progress : nil,
            errorMessage: errorMessage,
            primaryTitle: "Sync",
            isPrimaryDisabled: remotes.isEmpty || repository.currentBranch == nil,
            onCancel: { dismiss() },
            onPrimary: performSync
        ) {
            DialogCard {
                DialogField("Remote") {
                    Picker("Remote", selection: $selectedRemote) {
                        ForEach(remotes) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    .disabled(remotes.isEmpty)
                }
                PullStrategyField(strategy: $strategy)
            }
            if !tracksSelectedRemote {
                Banner(symbol: "arrow.up.to.line",
                       message: "'\(branchName)' doesn't track \(selectedRemote) yet. Sync pushes it to \(selectedRemote)/\(branchName) and sets that as its upstream.")
            }
        }
        .task { strategy = await repository.defaultPullStrategy() }
    }

    private var branchName: String { repository.currentBranch?.name ?? "HEAD" }

    private var tracksSelectedRemote: Bool {
        repository.currentBranch?.upstream != nil && repository.currentBranch?.upstreamRemoteName == selectedRemote
    }

    private func performSync() {
        isSyncing = true
        errorMessage = nil
        progress = 0
        Task {
            do {
                try await repository.sync(remote: selectedRemote, strategy: strategy) { value in
                    Task { @MainActor in progress = value }
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSyncing = false
                onComplete()
            }
        }
    }
}

#Preview {
    SyncDialogView(repository: MockGitRepository(), remotes: MockData.remotes)
}
