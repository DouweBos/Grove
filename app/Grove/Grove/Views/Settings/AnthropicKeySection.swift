// Views/Settings/AnthropicKeySection.swift
// Grove
//
// Accounts > Anthropic: the API key the commit composer's Draft button uses, stored in the Keychain.

import SwiftUI

struct AnthropicKeySection: View {

    @State private var hasKey = AnthropicKeyStore.hasKey
    @State private var draftKey = ""
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if hasKey {
                LabeledContent("API Key") {
                    HStack(spacing: Theme.Spacing.sm) {
                        StatusBadge(title: "Saved in Keychain", symbol: "checkmark.circle.fill", tone: .positive)
                        Button("Remove", role: .destructive) { remove() }
                    }
                }
            } else {
                LabeledContent("API Key") {
                    HStack(spacing: Theme.Spacing.sm) {
                        SecureField("sk-ant-\u{2026}", text: $draftKey)
                            .labelsHidden()
                            .font(.monoCaption)
                            .frame(minWidth: 240)
                            .onSubmit(save)
                        Button("Save", action: save)
                            .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Anthropic")
        } footer: {
            Text("Used by Draft in the commit composer (\(CommitMessageDrafter.model)). "
                 + "The staged diff is sent to Anthropic only when you click Draft. Create a key at console.anthropic.com.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func save() {
        do {
            try AnthropicKeyStore.save(draftKey)
            draftKey = ""
            errorMessage = nil
            hasKey = AnthropicKeyStore.hasKey
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try AnthropicKeyStore.delete()
            errorMessage = nil
            hasKey = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    Form { AnthropicKeySection() }
        .formStyle(.grouped)
        .frame(width: 520, height: 240)
}
