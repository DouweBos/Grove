// Views/Repositories/CreateRepositorySheet.swift
// Grove

import GroveKit
import SwiftUI
import UniformTypeIdentifiers

/// Initialises a new empty repository and opens it.
struct CreateRepositorySheet: View {

    @Environment(WindowViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var destinationURL: URL?
    @State private var isPickerPresented = false
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        DialogSheet(
            title: "New Repository",
            message: "Runs git init in the chosen folder, adds it to your list and opens it.",
            symbol: "plus.square.on.square",
            progress: isCreating ? "Creating repository…" : nil,
            errorMessage: error,
            primaryTitle: "Create",
            isPrimaryDisabled: destinationURL == nil,
            onCancel: { dismiss() },
            onPrimary: performCreate
        ) {
            DialogCard {
                DialogField("Folder") {
                    DialogPathField(path: destinationURL?.path) { isPickerPresented = true }
                }
            }
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { destinationURL = url }
        }
    }

    private func performCreate() {
        guard let url = destinationURL else { return }
        isCreating = true
        error = nil
        Task {
            do {
                let repo = try await viewModel.manager.initRepository(at: url)
                viewModel.selectBookmark(viewModel.manager.bookmarks.first(where: { $0.path == repo.path.path })?.id)
                dismiss()
                viewModel.openReference(RepositoryReference(path: url.path))
            } catch {
                self.error = error.localizedDescription
                isCreating = false
            }
        }
    }
}

#Preview {
    CreateRepositorySheet()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
