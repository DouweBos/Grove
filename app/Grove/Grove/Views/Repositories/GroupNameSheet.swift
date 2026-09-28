// Views/Repositories/GroupNameSheet.swift
// Grove

import SwiftUI

/// Names a new bookmark group or renames an existing one.
struct GroupNameSheet: View {

    @Environment(WindowViewModel.self) private var viewModel
    let editor: GroupEditor

    @State private var name = ""

    private var isRename: Bool {
        if case .rename = editor { return true }
        return false
    }

    var body: some View {
        DialogSheet(
            title: isRename ? "Rename Group" : "New Group",
            message: "Groups keep related repositories together in the sidebar.",
            symbol: "folder",
            width: 400,
            primaryTitle: isRename ? "Rename" : "Create",
            isPrimaryDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { viewModel.dismissGroupEditor() },
            onPrimary: { viewModel.commitGroupEditor(name: name) }
        ) {
            DialogCard {
                DialogField("Name") {
                    TextField("Work", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onAppear {
            if case .rename(let group) = editor { name = group.name }
        }
    }
}

#Preview {
    GroupNameSheet(editor: .new)
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
