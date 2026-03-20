// Views/Dialogs/PushDialogView.swift
// Grove
//
// Push dialog: destination dropdown, collapsible
// Options section with Tags / Force Push / Submodules / Skip Hooks.

import SwiftUI

// MARK: - PushDialogView

/// Dialog for pushing commits to a remote branch.
///
/// Destination picker,
/// collapsible options, Cancel + "Push HEAD" primary button.
struct PushDialogView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: State

    let repository: any GitRepositoryProtocol
    let branches: [BranchInfo]
    let remotes: [RemoteInfo]

    @State private var selectedRemote = "origin"
    @State private var selectedDestination = "origin/main"
    @State private var pushAllTags = false
    @State private var forcePush = false
    @State private var recurseSubmodules = false
    @State private var skipHooks = false
    @State private var isPushing = false
    @State private var errorMessage: String?

    init(
        repository: any GitRepositoryProtocol,
        branches: [BranchInfo] = [],
        remotes: [RemoteInfo] = []
    ) {
        self.repository = repository
        self.branches = branches
        self.remotes = remotes
        let head = branches.first(where: { $0.isHEAD })
        _selectedDestination = State(initialValue: head.flatMap { $0.upstream } ?? "origin/main")
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Push HEAD",
                description: "Pushes new commits from your local HEAD branch '\(repository.currentBranch?.name ?? "main")' to the chosen remote branch."
            )

            Divider()

            Form {
                LabeledContent("Destination") {
                    Picker("", selection: $selectedDestination) {
                        ForEach(remoteBranchOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            DialogOptionsSection {
                DialogOptionRow(
                    isOn: $pushAllTags,
                    label: "Push All Tags",
                    description: "All refs under refs/tags are pushed."
                )
                Divider().padding(.vertical, 4)
                DialogOptionRow(
                    isOn: $forcePush,
                    label: "Force Push",
                    description: "Enforces a new history on the remote branch. Use with care."
                )
                Divider().padding(.vertical, 4)
                DialogOptionRow(
                    isOn: $recurseSubmodules,
                    label: "Recurse Submodules",
                    description: "Ensures that all submodule commits referenced by the project have been pushed."
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
                primaryLabel: isPushing ? "Pushing…" : "Push HEAD",
                primaryAction: performPush,
                isPrimaryDisabled: isPushing
            )
        }
        .frame(width: 460)
    }

    // MARK: Helpers

    private var remoteBranchOptions: [String] {
        guard !remotes.isEmpty else { return [selectedDestination] }
        return remotes.flatMap { remote in
            branches
                .filter { $0.isLocal }
                .map { "\(remote.name)/\($0.name)" }
        }
    }

    private func performPush() {
        isPushing = true
        errorMessage = nil
        Task {
            do {
                try await repository.push(
                    remote: selectedRemote.isEmpty ? nil : selectedRemote,
                    force: forcePush,
                    forceLease: !forcePush,
                    progress: nil
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isPushing = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PushDialogView(
        repository: MockGitRepository(),
        branches: MockData.branches,
        remotes: MockData.remotes
    )
}
