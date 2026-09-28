// Views/Dialogs/CreateBranchDialogView.swift
// Grove

import SwiftUI

/// Creates a local branch from a branch, tag or commit.
struct CreateBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let localBranches: [BranchInfo]
    let onCreated: ((BranchInfo) -> Void)?

    @State private var branchName = ""
    @State private var startingPoint: String
    @State private var checkoutAfterCreate = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(
        repository: any GitRepositoryProtocol,
        localBranches: [BranchInfo] = [],
        fromRef: String? = nil,
        onCreated: ((BranchInfo) -> Void)? = nil
    ) {
        self.repository = repository
        self.localBranches = localBranches
        self.onCreated = onCreated
        let head = localBranches.first(where: { $0.isHEAD })?.name ?? repository.currentBranch?.name ?? "HEAD"
        _startingPoint = State(initialValue: fromRef ?? head)
    }

    private var trimmedName: String { branchName.trimmingCharacters(in: .whitespaces) }
    private var isValidName: Bool { !trimmedName.isEmpty && !trimmedName.contains(" ") }

    /// Local branches plus the requested ref when it isn't one (a tag, SHA or remote branch).
    private var startingPoints: [String] {
        let names = localBranches.map(\.name)
        return names.contains(startingPoint) ? names : [startingPoint] + names
    }

    var body: some View {
        DialogSheet(
            title: "New Branch",
            message: "Creates a local branch starting at the chosen branch, tag or commit.",
            symbol: "arrow.triangle.branch",
            width: 440,
            progress: isCreating ? "Creating \(trimmedName)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Create Branch",
            isPrimaryDisabled: !isValidName,
            onCancel: { dismiss() },
            onPrimary: performCreate
        ) {
            DialogCard {
                DialogField("Name") {
                    TextField("feature/my-feature", text: $branchName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(performCreate)
                }
                DialogField("Starting At") {
                    Picker("Starting At", selection: $startingPoint) {
                        ForEach(startingPoints, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                DialogOptionRow(isOn: $checkoutAfterCreate, label: "Check Out After Creating")
            }
        }
    }

    private func performCreate() {
        guard isValidName, !isCreating else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let branch = try await repository.createBranch(name: trimmedName, from: startingPoint, checkout: checkoutAfterCreate)
                onCreated?(branch)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

#Preview {
    CreateBranchDialogView(repository: MockGitRepository(), localBranches: MockData.branches.filter(\.isLocal))
}
