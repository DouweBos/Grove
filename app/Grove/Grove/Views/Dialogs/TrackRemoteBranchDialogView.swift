// Views/Dialogs/TrackRemoteBranchDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Sets the remote branch a local branch pulls from and compares against.
struct TrackRemoteBranchDialogView: View {
    let viewModel: SidebarViewModel
    let branch: BranchInfo

    @Environment(\.dismiss) private var dismiss
    @State private var remoteBranch: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(viewModel: SidebarViewModel, branch: BranchInfo) {
        self.viewModel = viewModel
        self.branch = branch
        _remoteBranch = State(initialValue: viewModel.actions.suggestedUpstream(for: branch) ?? viewModel.actions.trackableRemoteBranches.first ?? "")
    }

    private var candidates: [String] { viewModel.actions.trackableRemoteBranches }

    var body: some View {
        DialogSheet(
            title: "Track Remote Branch",
            message: "\u{201C}\(branch.name)\u{201D} pulls from this branch, and Grove shows how far ahead or behind of it you are.",
            symbol: "arrow.left.arrow.right",
            progress: isSaving ? "Tracking \(remoteBranch)…" : nil,
            errorMessage: errorMessage ?? (candidates.isEmpty ? "There are no remote branches. Add a remote or fetch first." : nil),
            primaryTitle: "Track",
            isPrimaryDisabled: remoteBranch.isEmpty || remoteBranch == branch.upstreamShortName || isSaving,
            onCancel: { dismiss() },
            onPrimary: save
        ) {
            DialogCard {
                DialogField("Remote Branch") {
                    Picker("Remote Branch", selection: $remoteBranch) {
                        ForEach(candidates, id: \.self) { Text($0).font(.monoCaption).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(candidates.isEmpty)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.actions.track(branch, remoteBranch: remoteBranch)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.refs.replace(remoteBranches: MockData.branches.filter(\.isRemote), remotes: MockData.remotes)
    return TrackRemoteBranchDialogView(viewModel: vm, branch: MockData.branches.first { $0.isLocal }!)
}
