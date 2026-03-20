// Views/Dialogs/CreateTagDialogView.swift
// Grove
//
// Dialog for creating a lightweight or annotated tag.

import SwiftUI

// MARK: - CreateTagDialogView

/// Dialog for creating a Git tag at a specific commit.
struct CreateTagDialogView: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: Dependencies

    let repository: any GitRepositoryProtocol
    /// SHA to tag. `nil` means tag HEAD.
    var targetSHA: String?
    let onCreated: ((TagInfo) -> Void)?

    // MARK: State

    @State private var tagName = ""
    @State private var tagMessage = ""
    @State private var isAnnotated = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    // MARK: Init

    init(
        repository: any GitRepositoryProtocol,
        targetSHA: String? = nil,
        onCreated: ((TagInfo) -> Void)? = nil
    ) {
        self.repository = repository
        self.targetSHA = targetSHA
        self.onCreated = onCreated
    }

    // MARK: Computed

    private var isValidName: Bool {
        let name = tagName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !name.contains(" ")
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Create Tag",
                description: targetSHA.map { "Tag commit \(String($0.prefix(7)))." }
                    ?? "Tag the current HEAD commit."
            )

            Divider()

            Form {
                LabeledContent("Tag Name") {
                    TextField("v1.0.0", text: $tagName)
                        .textFieldStyle(.plain)
                }

                Toggle("Annotated Tag", isOn: $isAnnotated)

                if isAnnotated {
                    LabeledContent("Message") {
                        TextEditor(text: $tagMessage)
                            .frame(minHeight: 60, maxHeight: 120)
                            .font(.body)
                    }
                }
            }
            .formStyle(.grouped)
            .animation(.easeInOut(duration: 0.15), value: isAnnotated)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Divider()

            SheetFooter(
                cancelAction: { dismiss() },
                primaryLabel: isCreating ? "Creating…" : "Create Tag",
                primaryAction: performCreate,
                isPrimaryDisabled: !isValidName || isCreating
            )
        }
        .frame(width: 400)
    }

    // MARK: Actions

    private func performCreate() {
        let name = tagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        errorMessage = nil
        let message: String? = isAnnotated && !tagMessage.isEmpty ? tagMessage : nil
        Task {
            do {
                let tag = try await repository.createTag(
                    name: name,
                    at: targetSHA,
                    message: message
                )
                onCreated?(tag)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CreateTagDialogView(repository: MockGitRepository())
}
