// Views/Dialogs/PullDialogView.swift
// Grove
//
// Pull dialog: remote branch picker, Rebase toggle,
// collapsible Options (Verify Signatures, Skip Hooks).

import SwiftUI

// MARK: - PullDialogView

/// Dialog for pulling from a remote branch.
///
/// Remote branch dropdown, prominent
/// "Use Rebase Instead of Merge" toggle, collapsible options section.
struct PullDialogView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: Dependencies

    let repository: any GitRepositoryProtocol
    let remoteBranches: [BranchInfo]
    let remotes: [RemoteInfo]

    // MARK: State

    @State private var selectedRemoteBranch: String
    @State private var useRebase = false
    @State private var verifySignatures = false
    @State private var skipHooks = false
    @State private var isPulling = false
    @State private var errorMessage: String?

    // MARK: Init

    init(
        repository: any GitRepositoryProtocol,
        remoteBranches: [BranchInfo] = [],
        remotes: [RemoteInfo] = []
    ) {
        self.repository = repository
        self.remoteBranches = remoteBranches
        self.remotes = remotes
        let upstream = repository.currentBranch?.upstream ?? "origin/main"
        let shortName = upstream.replacingOccurrences(of: "refs/remotes/", with: "")
        _selectedRemoteBranch = State(initialValue: shortName)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Pull",
                description: "Fetches changes from the chosen remote branch and integrates them into your local HEAD branch."
            )

            Divider()

            Form {
                LabeledContent("Remote Branch") {
                    Picker("", selection: $selectedRemoteBranch) {
                        ForEach(remoteBranchNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Use Rebase Instead of Merge", isOn: $useRebase)
                        .fontWeight(.medium)
                    Text("Rebases the local HEAD branch onto the fetched revisions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.vertical, 4)
            }
            .formStyle(.grouped)

            DialogOptionsSection {
                DialogOptionRow(
                    isOn: $verifySignatures,
                    label: "Verify Signatures",
                    description: "Merge is aborted if the tip commit of the side branch is not signed with a valid key."
                )
                Divider().padding(.vertical, 4)
                DialogOptionRow(
                    isOn: $skipHooks,
                    label: "Skip Hooks",
                    description: "Bypasses any associated hook scripts."
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
                primaryLabel: isPulling ? "Pulling…" : "Pull",
                primaryAction: performPull,
                isPrimaryDisabled: isPulling
            )
        }
        .frame(width: 460)
    }

    // MARK: Helpers

    private var remoteBranchNames: [String] {
        guard !remoteBranches.isEmpty else { return [selectedRemoteBranch] }
        return remoteBranches.map { $0.name }
    }

    private func performPull() {
        isPulling = true
        errorMessage = nil
        Task {
            do {
                try await repository.pull(
                    remote: nil,
                    rebase: useRebase,
                    progress: nil
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isPulling = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PullDialogView(
        repository: MockGitRepository(),
        remoteBranches: MockData.branches.filter(\.isRemote),
        remotes: MockData.remotes
    )
}
