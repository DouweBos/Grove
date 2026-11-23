// Views/Repositories/AddRepositorySheet.swift
// Grove

import GroveUIKit
import SwiftUI
import UniformTypeIdentifiers

/// Adds an existing local repository to the browser.
struct AddRepositorySheet: View {

    @Environment(WindowViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedURL: URL?
    @State private var isPickerPresented = false
    @State private var groupID: UUID?

    var body: some View {
        GitDialogSheet(
            title: "Add Repository",
            message: "Choose a folder that already contains a Git repository.",
            symbol: "folder.badge.plus",
            primaryTitle: "Add",
            isPrimaryDisabled: selectedURL == nil,
            onCancel: { dismiss() },
            onPrimary: {
                guard let url = selectedURL else { return }
                viewModel.addRepository(at: url, groupID: groupID)
                dismiss()
            }
        ) {
            GitDialogCard {
                GitDialogField("Folder") {
                    GitDialogPathField(path: selectedURL.map { abbreviatingHome($0.path) }) { isPickerPresented = true }
                }
                if !viewModel.sortedGroups.isEmpty {
                    GitDialogField("Group") {
                        Picker("Group", selection: $groupID) {
                            Text("None").tag(UUID?.none)
                            ForEach(viewModel.sortedGroups) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { selectedURL = url }
        }
        .onAppear { groupID = viewModel.selectedBookmark?.groupID }
    }
}

#Preview {
    AddRepositorySheet()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
