// Views/Repositories/AddRepositorySheet.swift
// Grove
//
// Sheet for adding an existing local repository to the browser.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - AddRepositorySheet

/// Sheet presented when the user clicks "Add" in the repository browser.
///
/// Opens a folder picker and bookmarks the chosen directory.
struct AddRepositorySheet: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedURL: URL?
    @State private var isPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SheetHeader(
                title: "Add Repository",
                description: "Choose a local folder that contains an existing Git repository."
            )

            Divider()

            // Fields
            Form {
                LabeledContent("Repository") {
                    HStack {
                        Text(selectedURL?.path ?? "No folder selected")
                            .foregroundStyle(selectedURL == nil ? .secondary : .primary)
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
                    selectedURL = url
                }
            }

            Divider()

            // Footer
            SheetFooter(
                cancelAction: { dismiss() },
                primaryLabel: "Add",
                primaryAction: {
                    guard let url = selectedURL else { return }
                    viewModel.addBookmark(path: url.path, displayName: url.lastPathComponent)
                    dismiss()
                },
                isPrimaryDisabled: selectedURL == nil
            )
        }
        .frame(width: 460)
    }
}

// MARK: - Preview

#Preview {
    AddRepositorySheet()
        .environment(RepositoryBrowserViewModel(manager: MockRepositoryManager()))
}
