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
    /// Clone from Subversion with git svn instead of from a git remote.
    @State private var isSubversion = false
    @State private var standardLayout = true

    init(initialURL: String? = nil) {
        _cloneURL = State(initialValue: initialURL ?? "")
    }

    private var parent: URL {
        parentOverride ?? URL(fileURLWithPath: (defaultCloneDirectory as NSString).expandingTildeInPath)
    }

    private var trimmedURL: String { cloneURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "grove" from "git@github.com:org/grove.git", "https://host/org/grove" or "https://svn.host/grove/trunk".
    private var suggestedName: String {
        var parts = trimmedURL.split(whereSeparator: { $0 == "/" || $0 == ":" }).map(String.init)
        if isSubversion, parts.count > 1, parts.last == "trunk" { parts.removeLast() }
        let last = parts.last ?? ""
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
                DialogField("From") {
                    Picker("From", selection: $isSubversion) {
                        Text("Git").tag(false)
                        Text("Subversion").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                DialogField("URL") {
                    TextField(isSubversion ? "https://svn.example.com/project" : "https://github.com/org/repo.git", text: $cloneURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                if isSubversion {
                    DialogOptionRow(isOn: $standardLayout, label: "Standard Layout",
                                    description: "Maps trunk, branches and tags to git branches and tags (git svn clone --stdlayout).")
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
        if isSubversion { return "Importing SVN revisions…" }
        return switch cloneProgress?.phase {
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
        let fromSubversion = isSubversion
        let layout = standardLayout
        Task {
            do {
                // git svn replays every revision, so it has no object counts to report as it goes.
                let repo = fromSubversion
                    ? try await viewModel.manager.cloneSVNRepository(url: url, to: target, standardLayout: layout)
                    : try await viewModel.manager.cloneRepository(url: url, to: target) { progress in
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
