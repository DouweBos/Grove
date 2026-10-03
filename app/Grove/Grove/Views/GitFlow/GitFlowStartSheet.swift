// Views/GitFlow/GitFlowStartSheet.swift
// Grove

import GroveKit
import SwiftUI

/// Starts a feature, release or hotfix branch from git-flow's base for it (or another branch).
struct GitFlowStartSheet: View {
    let viewModel: GitFlowViewModel
    let kind: GitFlowKind

    @State private var name = ""
    @State private var base: String

    init(viewModel: GitFlowViewModel, kind: GitFlowKind) {
        self.viewModel = viewModel
        self.kind = kind
        _base = State(initialValue: viewModel.config?.base(for: kind) ?? "")
    }

    private var config: GitFlowConfig { viewModel.config ?? GitFlowConfig() }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var branchName: String { config.branchName(kind, trimmedName.isEmpty ? kind.namePrompt : trimmedName) }

    private var bases: [String] {
        let names = viewModel.refs.localBranches.map(\.name)
        return names.contains(base) ? names : [base] + names
    }

    var body: some View {
        DialogSheet(
            title: "Start \(kind.title)",
            message: "Creates \(branchName) from \(base) and checks it out.",
            symbol: kind.symbol,
            progress: viewModel.isRunning ? "Creating \(branchName)…" : nil,
            errorMessage: viewModel.errorMessage,
            primaryTitle: "Start \(kind.title)",
            isPrimaryDisabled: trimmedName.isEmpty || trimmedName.contains(" "),
            onCancel: viewModel.dismissSheet,
            onPrimary: start
        ) {
            DialogCard {
                DialogField(kind == .feature ? "Name" : "Version") {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(config.prefix(for: kind)).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                        TextField(kind.namePrompt, text: $name)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(start)
                    }
                }
                DialogField("Starting At") {
                    Picker("Starting At", selection: $base) {
                        ForEach(bases, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private func start() {
        guard !trimmedName.isEmpty, !trimmedName.contains(" ") else { return }
        let base = base == config.base(for: kind) ? nil : base
        Task { await viewModel.start(kind, name: trimmedName, base: base) }
    }
}

#Preview {
    let repo = MockGitRepository()
    GitFlowStartSheet(viewModel: GitFlowViewModel(repository: repo, refs: RepositoryRefs(repository: repo)), kind: .feature)
}
