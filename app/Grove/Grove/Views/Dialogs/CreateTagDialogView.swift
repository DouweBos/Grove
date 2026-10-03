// Views/Dialogs/CreateTagDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Creates a lightweight or annotated tag at HEAD or a given commit.
struct CreateTagDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    /// SHA to tag; nil tags HEAD.
    var targetSHA: String?
    let onCreated: ((TagInfo) -> Void)?

    @State private var tagName = ""
    @State private var tagMessage = ""
    @State private var isAnnotated = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, targetSHA: String? = nil, onCreated: ((TagInfo) -> Void)? = nil) {
        self.repository = repository
        self.targetSHA = targetSHA
        self.onCreated = onCreated
    }

    private var trimmedName: String { tagName.trimmingCharacters(in: .whitespaces) }
    private var isValidName: Bool { !trimmedName.isEmpty && !trimmedName.contains(" ") }

    var body: some View {
        DialogSheet(
            title: "New Tag",
            message: targetSHA.map { "Marks commit \(String($0.prefix(7))) with a name, e.g. a release." }
                ?? "Marks the current HEAD commit with a name, e.g. a release.",
            symbol: "tag",
            width: 440,
            progress: isCreating ? "Creating \(trimmedName)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Create Tag",
            isPrimaryDisabled: !isValidName,
            onCancel: { dismiss() },
            onPrimary: performCreate
        ) {
            DialogCard {
                DialogField("Name") {
                    TextField("v1.0.0", text: $tagName)
                        .textFieldStyle(.roundedBorder)
                }
                DialogOptionRow(
                    isOn: $isAnnotated,
                    label: "Annotated",
                    description: "Stores a message, author and date with the tag."
                )
                if isAnnotated {
                    DialogField("Message") {
                        TextEditor(text: $tagMessage)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Spacing.xs)
                            .frame(height: 72)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isAnnotated)
        }
    }

    private func performCreate() {
        guard isValidName else { return }
        isCreating = true
        errorMessage = nil
        let message: String? = isAnnotated && !tagMessage.isEmpty ? tagMessage : nil
        Task {
            do {
                let tag = try await repository.createTag(name: trimmedName, at: targetSHA, message: message)
                onCreated?(tag)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

#Preview {
    CreateTagDialogView(repository: MockGitRepository())
}
