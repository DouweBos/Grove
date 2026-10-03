// Views/GitFlow/GitFlowFinishSheet.swift
// Grove

import GroveKit
import SwiftUI

/// Finishes a feature, release or hotfix: merges it where git-flow merges it, with the finish options.
struct GitFlowFinishSheet: View {
    let viewModel: GitFlowViewModel
    let kind: GitFlowKind

    @State private var name: String
    @State private var options = GitFlowFinishOptions()
    @State private var createsTag = true
    @State private var tagMessage = ""

    init(viewModel: GitFlowViewModel, kind: GitFlowKind, name: String?) {
        self.viewModel = viewModel
        self.kind = kind
        let current = viewModel.currentFlowBranch.flatMap { $0.kind == kind ? $0.name : nil }
        _name = State(initialValue: name ?? current ?? viewModel.branchNames(of: kind).first ?? "")
    }

    private var config: GitFlowConfig { viewModel.config ?? GitFlowConfig() }
    private var branch: String { config.branchName(kind, name) }
    private var tagName: String { config.versionTagPrefix + name }

    private var summary: String {
        switch kind {
        case .feature:
            return "Merges \(branch) into \(config.developBranch)."
        case .release, .hotfix:
            return "Merges \(branch) into \(config.productionBranch)\(createsTag ? ", tags it \(tagName)," : "") and back into "
                + (kind == .hotfix && !viewModel.branchNames(of: .release).isEmpty ? "the release in progress." : "\(config.developBranch).")
        }
    }

    var body: some View {
        DialogSheet(
            title: "Finish \(kind.title)",
            message: summary + " Conflicts stop the finish for you to resolve.",
            symbol: kind.symbol,
            progress: viewModel.isRunning ? "Finishing \(branch)…" : nil,
            errorMessage: viewModel.errorMessage,
            primaryTitle: "Finish \(kind.title)",
            isPrimaryDisabled: name.isEmpty || (kind.isTagged && createsTag && tagMessage.trimmingCharacters(in: .whitespaces).isEmpty),
            onCancel: viewModel.dismissSheet,
            onPrimary: finish
        ) {
            DialogCard {
                DialogField(kind.title) {
                    Picker(kind.title, selection: $name) {
                        ForEach(names, id: \.self) { Text(config.branchName(kind, $0)).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(names.isEmpty)
                }
                if kind.isTagged {
                    DialogOptionRow(isOn: $createsTag, label: "Tag \(tagName)", description: "An annotated tag on \(config.productionBranch).")
                    if createsTag {
                        DialogField("Tag Message") {
                            TextField("Release \(name)", text: $tagMessage).textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            DialogOptionsSection {
                if kind == .feature {
                    DialogOptionRow(isOn: $options.squash, label: "Squash Commits",
                                    description: "One commit on \(config.developBranch) instead of a merge commit.")
                }
                DialogOptionRow(isOn: $options.keepBranch, label: "Keep Branch", description: "Doesn't delete \(branch) afterwards.")
                DialogOptionRow(isOn: $options.push, label: "Push to origin",
                                description: "Pushes \(config.developBranch), \(config.productionBranch) and tags afterwards.")
            }
        }
        .onAppear { if tagMessage.isEmpty { tagMessage = "\(kind.title) \(name)" } }
        .onChange(of: name) { old, new in
            if tagMessage == "\(kind.title) \(old)" { tagMessage = "\(kind.title) \(new)" }
        }
    }

    private var names: [String] {
        let existing = viewModel.branchNames(of: kind)
        return name.isEmpty || existing.contains(name) ? existing : [name] + existing
    }

    private func finish() {
        var options = options
        options.tagMessage = kind.isTagged && createsTag ? tagMessage.trimmingCharacters(in: .whitespaces) : nil
        if kind != .feature { options.squash = false }
        Task { await viewModel.finish(kind, name: name, options: options) }
    }
}

#Preview {
    let repo = MockGitRepository()
    GitFlowFinishSheet(viewModel: GitFlowViewModel(repository: repo, refs: RepositoryRefs(repository: repo)), kind: .release, name: "1.2.0")
}
