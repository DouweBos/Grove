// Views/Dialogs/CloneDialogView.swift
// Grove
//
// Clone dialog: URL field, destination picker,
// optional LFS clone, Cancel + Clone buttons.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - CloneDialogView

/// Sheet for cloning a remote Git repository.
struct CloneDialogView: View {

    @Environment(WindowViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var cloneURL = ""
    @State private var destination: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Projects")
    @State private var isPickerPresented = false
    @State private var isCloning = false
    @State private var cloneProgress: CloneProgress?
    @State private var errorMessage: String?

    private var canClone: Bool {
        !cloneURL.trimmingCharacters(in: .whitespaces).isEmpty && !isCloning
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Clone Repository",
                description: "Enter the URL of the remote repository to clone, and choose a local destination folder."
            )

            Divider()

            Form {
                LabeledContent("Clone URL") {
                    TextField("https://github.com/org/repo.git", text: $cloneURL)
                        .textFieldStyle(.plain)
                }

                LabeledContent("Clone To") {
                    HStack {
                        Text(destination.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.primary)
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
                    destination = url
                }
            }

            if let progress = cloneProgress {
                CloneProgressView(progress: progress)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Divider()

            SheetFooter(
                cancelAction: {
                    dismiss()
                },
                primaryLabel: isCloning ? "Cloning…" : "Clone",
                primaryAction: performClone,
                isPrimaryDisabled: !canClone
            )
        }
        .frame(width: 460)
    }

    private func performClone() {
        isCloning = true
        errorMessage = nil
        let url = cloneURL.trimmingCharacters(in: .whitespaces)
        let dest = destination

        Task {
            do {
                let repo = try await viewModel.manager.cloneRepository(
                    url: url,
                    to: dest,
                    progress: { progress in
                        Task { @MainActor in
                            self.cloneProgress = progress
                        }
                    }
                )
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

// MARK: - CloneProgressView

private struct CloneProgressView: View {

    let progress: CloneProgress

    private var label: String {
        switch progress.phase {
        case .fetching: return "Fetching objects…"
        case .indexing: return "Indexing…"
        case .checkingOut: return "Checking out…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
        }
    }
}

// MARK: - Preview

#Preview {
    CloneDialogView()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
