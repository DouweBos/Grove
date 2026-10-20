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
    /// nil until git says what a plain pull does; the picker waits for it rather than showing Merge first.
    @State private var strategy: PullStrategy?
    @State private var operation = DialogOperation()
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, remotes: [RemoteInfo] = [], strategy: PullStrategy? = nil,
         onComplete: @escaping () -> Void = {}) {
        self.repository = repository
        self.remotes = remotes
        self.onComplete = onComplete
        _strategy = State(initialValue: strategy)
        let upstreamRemote = repository.currentBranch?.upstreamRemoteName
        _selectedRemote = State(initialValue: upstreamRemote ?? remotes.first?.name ?? "origin")
    }

    private var phase: String {
        switch operation.fraction {
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
            progress: operation.isRunning ? phase : nil,
            progressDetail: operation.isRunning ? selectedRemote : "",
            fraction: operation.isRunning ? operation.fraction : nil,
            errorMessage: errorMessage,
            primaryTitle: "Sync",
            isPrimaryDisabled: remotes.isEmpty || repository.currentBranch == nil || strategy == nil,
            onCancel: cancel,
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
        .task { if strategy == nil { strategy = await repository.defaultPullStrategy() } }
    }

    private var branchName: String { repository.currentBranch?.name ?? "HEAD" }

    private var tracksSelectedRemote: Bool {
        repository.currentBranch?.upstream != nil && repository.currentBranch?.upstreamRemoteName == selectedRemote
    }

    private func performSync() {
        guard let strategy else { return }
        errorMessage = nil
        let remote = selectedRemote
        operation.run({ progress in
            try await repository.sync(remote: remote, strategy: strategy, progress: progress)
        }, completion: { result in
            onComplete()
            switch result {
            case .success: dismiss()
            case .failure(let error): errorMessage = error.localizedDescription
            case nil: break
            }
        })
    }

    private func cancel() {
        operation.cancel()
        dismiss()
    }
}

#Preview {
    SyncDialogView(repository: MockGitRepository(), remotes: MockData.remotes)
}
