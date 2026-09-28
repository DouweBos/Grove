// Views/Repositories/GroupNameSheet.swift
// Grove

import SwiftUI

/// Names a new bookmark group, or renames a group or a repository.
struct GroupNameSheet: View {

    @Environment(WindowViewModel.self) private var viewModel
    let editor: GroupEditor

    @State private var name = ""

    var body: some View {
        DialogSheet(
            title: title,
            message: message,
            symbol: isRepository ? "arrow.triangle.branch" : "folder",
            width: 400,
            primaryTitle: isNew ? "Create" : "Rename",
            isPrimaryDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { viewModel.dismissGroupEditor() },
            onPrimary: { viewModel.commitGroupEditor(name: name) }
        ) {
            DialogCard {
                DialogField("Name") {
                    TextField(isRepository ? "Name" : "Work", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onAppear {
            switch editor {
            case .new: break
            case .rename(let group): name = group.name
            case .renameRepository(let bookmark): name = bookmark.displayName
            }
        }
    }

    private var isNew: Bool {
        if case .new = editor { return true }
        return false
    }

    private var isRepository: Bool {
        if case .renameRepository = editor { return true }
        return false
    }

    private var title: String {
        switch editor {
        case .new: "New Group"
        case .rename: "Rename Group"
        case .renameRepository: "Rename Repository"
        }
    }

    private var message: String {
        isRepository
            ? "The name shown in Grove. The folder on disk keeps its name."
            : "Groups keep related repositories together in the sidebar."
    }
}

#Preview {
    GroupNameSheet(editor: .new)
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
