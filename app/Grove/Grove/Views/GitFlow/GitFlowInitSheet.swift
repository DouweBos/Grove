// Views/GitFlow/GitFlowInitSheet.swift
// Grove

import GroveKit
import SwiftUI

/// Sets up git-flow: which branches are production and develop, and the branch and tag prefixes.
struct GitFlowInitSheet: View {
    let viewModel: GitFlowViewModel
    @State private var config: GitFlowConfig

    init(viewModel: GitFlowViewModel) {
        self.viewModel = viewModel
        _config = State(initialValue: viewModel.config ?? viewModel.suggestedConfig)
    }

    private var branchNames: [String] { viewModel.refs.localBranches.map(\.name) }

    private var isValid: Bool {
        let fields = [config.productionBranch, config.developBranch, config.featurePrefix, config.releasePrefix, config.hotfixPrefix]
        return fields.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } && config.productionBranch != config.developBranch
    }

    var body: some View {
        DialogSheet(
            title: "Initialize Git Flow",
            message: "Stores the branch model in this repository's config, creates the develop branch if it's missing and checks it out.",
            symbol: "arrow.triangle.branch",
            progress: viewModel.isRunning ? "Setting up git-flow…" : nil,
            errorMessage: viewModel.errorMessage,
            primaryTitle: "Initialize",
            isPrimaryDisabled: !isValid,
            onCancel: viewModel.dismissSheet,
            onPrimary: initialize
        ) {
            DialogCard {
                DialogField("Production") {
                    Picker("Production", selection: $config.productionBranch) {
                        ForEach(options(including: config.productionBranch), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                DialogField("Develop") {
                    TextField("develop", text: $config.developBranch).textFieldStyle(.roundedBorder)
                }
            }
            DialogCard {
                DialogField("Features") { prefixField("feature/", text: $config.featurePrefix) }
                DialogField("Releases") { prefixField("release/", text: $config.releasePrefix) }
                DialogField("Hotfixes") { prefixField("hotfix/", text: $config.hotfixPrefix) }
                DialogField("Version Tags") { prefixField("none, e.g. v", text: $config.versionTagPrefix) }
            }
        }
    }

    private func initialize() {
        Task { await viewModel.initialize(config) }
    }

    private func prefixField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text).textFieldStyle(.roundedBorder).font(.monoCaption)
    }

    private func options(including name: String) -> [String] {
        branchNames.contains(name) ? branchNames : [name] + branchNames
    }
}

#Preview {
    let repo = MockGitRepository()
    GitFlowInitSheet(viewModel: GitFlowViewModel(repository: repo, refs: RepositoryRefs(repository: repo)))
}
