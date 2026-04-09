// Views/Repositories/CreateRepositorySheet.swift
// Grove
//
// Sheet for initialising a new empty repository.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - CreateRepositorySheet

/// Sheet for initialising a new Git repository at a chosen location.
struct CreateRepositorySheet: View {

    @Environment(WindowViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var destinationURL: URL?
    @State private var isPickerPresented = false
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Create Repository",
                description: "Initialise a new empty Git repository in the chosen folder."
            )

            Divider()

            Form {
                LabeledContent("Location") {
                    HStack {
                        Text(destinationURL?.path ?? "No folder selected")
                            .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Choose...") {
                            isPickerPresented = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    destinationURL = url
                }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
            }

            Divider()

            SheetFooter(
                cancelAction: { dismiss() },
                primaryLabel: isCreating ? "Creating..." : "Create",
                primaryAction: performCreate,
                isPrimaryDisabled: destinationURL == nil || isCreating
            )
        }
        .frame(width: 460)
    }

    private func performCreate() {
        guard let url = destinationURL else { return }
        isCreating = true
        Task {
            do {
                let repo = try await viewModel.manager.initRepository(at: url)
                viewModel.selectedBookmarkID = viewModel.manager.bookmarks
                    .first(where: { $0.path == repo.path.path })?.id
                dismiss()
                viewModel.openReference(RepositoryReference(path: url.path))
            } catch {
                self.error = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Preview

#Preview {
    CreateRepositorySheet()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
