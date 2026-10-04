// Views/Dialogs/AddSubmoduleDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Clones a repository into a folder of this one as a submodule.
struct AddSubmoduleDialogView: View {
    let viewModel: SidebarViewModel

    @State private var url = ""
    @State private var path = ""
    @State private var branch = ""
    @State private var pathEdited = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPath: String { path.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        DialogSheet(
            title: "Add Submodule",
            message: "Clones the repository into a folder here and stages .gitmodules and the submodule, ready to commit.",
            symbol: "shippingbox",
            progress: isAdding ? "Cloning \(trimmedURL)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Add Submodule",
            isPrimaryDisabled: trimmedURL.isEmpty || trimmedPath.isEmpty,
            onCancel: viewModel.dismissAddSubmodule,
            onPrimary: add
        ) {
            DialogCard {
                DialogField("URL") {
                    TextField("https://github.com/owner/repository.git", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                DialogField("Path") {
                    TextField("vendor/library", text: Binding(get: { path }, set: { path = $0; pathEdited = true }))
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                DialogField("Branch") {
                    TextField("Remote default", text: $branch)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
            }
        }
        .onChange(of: url) { _, new in
            if !pathEdited { path = RefActionsViewModel.suggestedSubmodulePath(for: new) }
        }
    }

    private func add() {
        guard !trimmedURL.isEmpty, !trimmedPath.isEmpty else { return }
        isAdding = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.actions.addSubmodule(url: trimmedURL, path: trimmedPath,
                                                         branch: branch.trimmingCharacters(in: .whitespaces))
                viewModel.dismissAddSubmodule()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
}

#Preview {
    AddSubmoduleDialogView(viewModel: SidebarViewModel(repository: MockGitRepository()))
}
