// Views/Settings/CommitTemplatesPreferencesTab.swift
// Grove
//
// Commit message templates preferences: create, edit, reorder and set a default template.

import SwiftUI

// MARK: - PreferencesCommitTemplate Model

/// A named commit message template used in the commit dialog.
struct PreferencesCommitTemplate: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var body: String
    var isDefault: Bool
}

// MARK: - CommitTemplatesPreferencesTab

/// Preferences tab for managing commit message templates.
struct CommitTemplatesPreferencesTab: View {

    @State private var templates: [PreferencesCommitTemplate] = [
        PreferencesCommitTemplate(
            name: "Conventional Commit",
            body: "feat: \n\n# Describe what this commit adds or changes.\n# Types: feat, fix, docs, style, refactor, test, chore",
            isDefault: true
        ),
        PreferencesCommitTemplate(
            name: "Bug Fix",
            body: "fix: \n\nCloses #",
            isDefault: false
        )
    ]

    @State private var selectedTemplateID: PreferencesCommitTemplate.ID?
    @State private var isDragging = false

    private var selectedTemplate: Binding<PreferencesCommitTemplate>? {
        guard let id = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == id }) else { return nil }
        return $templates[index]
    }

    var body: some View {
        HSplitView {
            templateList
                .frame(minWidth: 180, maxWidth: 220)

            if let template = selectedTemplate {
                templateEditor(template)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyEditor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Template List

    @ViewBuilder
    private var templateList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTemplateID) {
                ForEach(templates) { template in
                    TemplateRow(template: template)
                        .tag(template.id)
                }
                .onMove { source, destination in
                    templates.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 0) {
                Button {
                    addTemplate()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)

                Button {
                    removeSelectedTemplate()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(selectedTemplateID == nil)

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 30)
        }
    }

    // MARK: - Template Editor

    @ViewBuilder
    private func templateEditor(_ template: Binding<PreferencesCommitTemplate>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Template") {
                    LabeledContent("Name") {
                        TextField("Template name", text: template.name)
                    }

                    Toggle("Set as default template", isOn: template.isDefault)
                        .onChange(of: template.wrappedValue.isDefault) { _, newValue in
                            if newValue {
                                clearOtherDefaults(except: template.wrappedValue.id)
                            }
                        }
                }
            }
            .formStyle(.grouped)
            .frame(height: 140)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Message body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                TextEditor(text: template.body)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Empty Editor

    @ViewBuilder
    private var emptyEditor: some View {
        ContentUnavailableView(
            "No Template Selected",
            systemImage: "doc.text",
            description: Text("Select a template from the list or add a new one.")
        )
    }

    // MARK: - Actions

    private func addTemplate() {
        let template = PreferencesCommitTemplate(
            name: "New Template",
            body: "",
            isDefault: templates.isEmpty
        )
        templates.append(template)
        selectedTemplateID = template.id
    }

    private func removeSelectedTemplate() {
        guard let id = selectedTemplateID else { return }
        templates.removeAll { $0.id == id }
        selectedTemplateID = templates.first?.id
    }

    private func clearOtherDefaults(except keepID: UUID) {
        for index in templates.indices where templates[index].id != keepID {
            templates[index].isDefault = false
        }
    }
}

// MARK: - TemplateRow

private struct TemplateRow: View {
    let template: PreferencesCommitTemplate

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: template.isDefault ? "doc.text.fill" : "doc.text")
                .foregroundStyle(template.isDefault ? .orange : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(template.name.isEmpty ? "Untitled" : template.name)
                    .fontWeight(template.isDefault ? .semibold : .regular)
                    .lineLimit(1)
                Text(template.body.isEmpty ? "No content" : template.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    CommitTemplatesPreferencesTab()
        .frame(width: 540, height: 440)
}
