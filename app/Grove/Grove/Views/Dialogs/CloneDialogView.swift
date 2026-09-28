// Views/Dialogs/CloneDialogView.swift
// Grove

import SwiftUI
import UniformTypeIdentifiers

/// Starts cloning a remote repository into a new folder; the clone runs in the background and its row shows progress.
struct CloneDialogView: View {

    @Environment(WindowViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCloneDirectory") private var defaultCloneDirectory = "~/Projects"

    @State private var cloneURL: String
    @State private var folderName = ""
    @State private var parentOverride: URL?
    @State private var isPickerPresented = false
    @State private var errorMessage: String?

    init(initialURL: String? = nil) {
        _cloneURL = State(initialValue: initialURL ?? "")
    }

    private var parent: URL {
        parentOverride ?? URL(fileURLWithPath: (defaultCloneDirectory as NSString).expandingTildeInPath)
    }

    private var trimmedURL: String { cloneURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "grove" from "git@github.com:org/grove.git" or "https://host/org/grove".
    private var suggestedName: String {
        let last = trimmedURL.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }

    private var destination: URL {
        parent.appendingPathComponent(folderName.isEmpty ? suggestedName : folderName)
    }

    private var canClone: Bool { !trimmedURL.isEmpty && !destination.lastPathComponent.isEmpty }

    var body: some View {
        DialogSheet(
            title: "Clone Repository",
            message: "Downloads a copy of a remote repository in the background and adds it to your list.",
            symbol: "square.and.arrow.down",
            errorMessage: errorMessage,
            primaryTitle: "Clone",
            isPrimaryDisabled: !canClone,
            onCancel: { dismiss() },
            onPrimary: performClone
        ) {
            DialogCard {
                DialogField("URL") {
                    TextField("https://github.com/org/repo.git", text: $cloneURL.onSet { errorMessage = nil })
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                DialogField("Name") {
                    TextField(suggestedName.isEmpty ? "Folder name" : suggestedName, text: $folderName.onSet { errorMessage = nil })
                        .textFieldStyle(.roundedBorder)
                }
                DialogField("Location") {
                    DialogPathField(path: parent.path) { isPickerPresented = true }
                }
            }
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { parentOverride = url }
        }
    }

    /// Hands the clone to the window's queue and closes at once.
    private func performClone() {
        guard canClone else { return }
        if let problem = viewModel.clones.problem(cloning: trimmedURL, to: destination) {
            errorMessage = problem
            return
        }
        viewModel.clones.start(url: trimmedURL, destination: destination)
        dismiss()
    }
}

#Preview {
    CloneDialogView()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}

private extension Binding {
    /// The same binding, also running `action` on every write.
    func onSet(_ action: @escaping () -> Void) -> Binding {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; action() })
    }
}
