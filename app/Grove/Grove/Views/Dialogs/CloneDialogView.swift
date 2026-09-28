// Views/Dialogs/CloneDialogView.swift
// Grove

import SwiftUI
import UniformTypeIdentifiers

/// Clones a remote repository into a new folder and opens it.
struct CloneDialogView: View {

    @Environment(WindowViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCloneDirectory") private var defaultCloneDirectory = "~/Projects"

    @State private var cloneURL: String
    @State private var folderName = ""
    @State private var parentOverride: URL?
    @State private var isPickerPresented = false
    @State private var isCloning = false
    @State private var cloneProgress: CloneProgress?
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
            message: "Downloads a copy of a remote repository, adds it to your list and opens it.",
            symbol: "square.and.arrow.down",
            progress: isCloning ? progressTitle : nil,
            progressDetail: destination.lastPathComponent,
            errorMessage: errorMessage,
            primaryTitle: "Clone",
            isPrimaryDisabled: !canClone,
            onCancel: { dismiss() },
            onPrimary: performClone
        ) {
            DialogCard {
                DialogField("URL") {
                    TextField("https://github.com/org/repo.git", text: $cloneURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                DialogField("Name") {
                    TextField(suggestedName.isEmpty ? "Folder name" : suggestedName, text: $folderName)
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

    private var progressTitle: String {
        switch cloneProgress?.phase {
        case .indexing: "Indexing…"
        case .checkingOut: "Checking out files…"
        default: "Downloading objects…"
        }
    }

    private func performClone() {
        guard canClone else { return }
        isCloning = true
        errorMessage = nil
        let url = trimmedURL
        let target = destination
        Task {
            do {
                let repo = try await viewModel.manager.cloneRepository(url: url, to: target) { progress in
                    Task { @MainActor in cloneProgress = progress }
                }
                dismiss()
                viewModel.openReference(RepositoryReference(path: repo.path.path))
            } catch {
                errorMessage = error.localizedDescription
                isCloning = false
                cloneProgress = nil
            }
        }
    }
}

#Preview {
    CloneDialogView()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
