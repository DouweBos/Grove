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
    /// Clone from Subversion with git svn instead of from a git remote.
    @State private var isSubversion = false
    @State private var standardLayout = true
    @State private var isImportingSVN = false

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
            message: "Downloads a copy of a remote repository in the background and adds it to your list.",
            symbol: "square.and.arrow.down",
            progress: isImportingSVN ? "Importing SVN revisions\u{2026}" : nil,
            progressDetail: destination.lastPathComponent,
            errorMessage: errorMessage,
            primaryTitle: "Clone",
            isPrimaryDisabled: !canClone || isImportingSVN,
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
                    TextField(isSubversion ? "https://svn.example.com/project" : "https://github.com/org/repo.git",
                              text: $cloneURL.onSet { errorMessage = nil })
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                if isSubversion {
                    DialogOptionRow(isOn: $standardLayout, label: "Standard Layout",
                                    description: "Maps trunk, branches and tags to git branches and tags (git svn clone --stdlayout).")
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

    /// Git clones go to the window's queue and the sheet closes at once; git svn has no progress to report, so it runs here.
    private func performClone() {
        guard canClone else { return }
        if isSubversion { return cloneFromSubversion() }
        if let problem = viewModel.clones.problem(cloning: trimmedURL, to: destination) {
            errorMessage = problem
            return
        }
        viewModel.clones.start(url: trimmedURL, destination: destination)
        dismiss()
    }

    private func cloneFromSubversion() {
        isImportingSVN = true
        errorMessage = nil
        let (url, target, layout) = (trimmedURL, destination, standardLayout)
        Task {
            do {
                let repo = try await viewModel.manager.cloneSVNRepository(url: url, to: target, standardLayout: layout)
                dismiss()
                viewModel.openReference(RepositoryReference(path: repo.path.path))
            } catch {
                errorMessage = error.localizedDescription
                isImportingSVN = false
            }
        }
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
