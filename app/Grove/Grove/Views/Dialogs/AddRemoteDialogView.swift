// Views/Dialogs/AddRemoteDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Adds a named remote and fetches it, so its branches appear in the sidebar.
struct AddRemoteDialogView: View {
    let viewModel: SidebarViewModel

    @State private var name: String
    @State private var url = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    init(viewModel: SidebarViewModel) {
        self.viewModel = viewModel
        _name = State(initialValue: viewModel.actions.suggestedRemoteName)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Only shown once something is typed, so an empty field doesn't open with an error.
    private var nameProblem: String? { name.isEmpty ? nil : viewModel.actions.remoteNameProblem(trimmedName) }

    var body: some View {
        DialogSheet(
            title: "Add Remote",
            message: "Connects this repository to another copy of it, such as one on GitHub, and fetches its branches.",
            symbol: "cloud",
            progress: isAdding ? "Adding \(trimmedName)…" : nil,
            errorMessage: errorMessage ?? nameProblem,
            primaryTitle: "Add Remote",
            isPrimaryDisabled: viewModel.actions.remoteNameProblem(trimmedName) != nil || trimmedURL.isEmpty || isAdding,
            onCancel: viewModel.dismissAddRemote,
            onPrimary: add
        ) {
            DialogCard {
                DialogField("Name") {
                    TextField("origin", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                DialogField("URL") {
                    TextField("https://github.com/owner/repository.git", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
            }
        }
        .onChange(of: name) { errorMessage = nil }
        .onChange(of: url) { errorMessage = nil }
    }

    private func add() {
        guard viewModel.actions.remoteNameProblem(trimmedName) == nil, !trimmedURL.isEmpty else { return }
        isAdding = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.actions.addRemote(name: trimmedName, url: trimmedURL) { viewModel.dismissAddRemote() }
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
}

#Preview {
    AddRemoteDialogView(viewModel: SidebarViewModel(repository: MockGitRepository()))
}
