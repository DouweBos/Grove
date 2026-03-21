// Views/Dialogs/CreateBranchDialogView.swift
// Grove
//
// Dialog for creating a new branch: name, starting point, track upstream,
// checkout after creation.

import SwiftUI

// MARK: - CreateBranchDialogView

/// Dialog for creating a new local branch.
struct CreateBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: Dependencies

    let repository: any GitRepositoryProtocol
    let localBranches: [BranchInfo]
    let onCreated: ((BranchInfo) -> Void)?

    // MARK: State

    @State private var branchName = ""
    @State private var startingPoint: String
    @State private var trackUpstream = true
    @State private var checkoutAfterCreate = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    // MARK: Init

    init(
        repository: any GitRepositoryProtocol,
        localBranches: [BranchInfo] = [],
        fromRef: String? = nil,
        onCreated: ((BranchInfo) -> Void)? = nil
    ) {
        self.repository = repository
        self.localBranches = localBranches
        self.onCreated = onCreated
        // Prefer the explicit `fromRef` when supplied (e.g. from a drag-and-drop).
        // Fall back to the current HEAD branch name, then "main".
        let head = localBranches.first(where: { $0.isHEAD })?.name ?? "main"
        _startingPoint = State(initialValue: fromRef ?? head)
    }

    // MARK: Computed

    private var isValidName: Bool {
        let name = branchName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !name.contains(" ")
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Create Branch",
                description: "Create a new local branch from the chosen starting point."
            )

            Divider()

            Form {
                LabeledContent("Branch Name") {
                    TextField("feature/my-feature", text: $branchName)
                        .textFieldStyle(.plain)
                }

                LabeledContent("Starting Point") {
                    Picker("", selection: $startingPoint) {
                        ForEach(localBranches, id: \.name) { branch in
                            HStack {
                                if branch.isHEAD {
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.orange)
                                }
                                Text(branch.name)
                            }
                            .tag(branch.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle("Track Remote Upstream", isOn: $trackUpstream)
                Toggle("Checkout After Creation", isOn: $checkoutAfterCreate)
            }
            .formStyle(.grouped)

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
                primaryLabel: isCreating ? "Creating…" : "Create Branch",
                primaryAction: performCreate,
                isPrimaryDisabled: !isValidName || isCreating
            )
        }
        .frame(width: 420)
    }

    // MARK: Actions

    private func performCreate() {
        let name = branchName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let branch = try await repository.createBranch(
                    name: name,
                    from: startingPoint,
                    checkout: checkoutAfterCreate
                )
                onCreated?(branch)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CreateBranchDialogView(
        repository: MockGitRepository(),
        localBranches: MockData.branches.filter(\.isLocal)
    )
}
