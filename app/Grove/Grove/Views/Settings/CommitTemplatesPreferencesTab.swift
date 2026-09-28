// Views/Settings/CommitTemplatesPreferencesTab.swift
// Grove
//
// Templates: add, edit, reorder and delete the commit message templates the composer offers.

import SwiftUI

struct CommitTemplatesPreferencesTab: View {

    var store: CommitTemplateStore = .shared
    @State private var selection: CommitTemplate.ID?

    private var selected: CommitTemplate? {
        store.templates.first { $0.id == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            templateList
                .frame(width: 210)
                .panel()
                .padding([.leading, .vertical], Theme.Spacing.lg)
            editor
        }
        .onAppear { if selection == nil { selection = store.templates.first?.id } }
    }

    // MARK: List

    private var templateList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.templates) { template in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name).font(.rowTitle).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        if !template.summary.isEmpty {
                            Text(template.summary).font(.monoCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    }
                    .tag(template.id)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            .scrollContentBackground(.hidden)
            Rectangle().fill(Theme.border).frame(height: 0.5)
            HStack(spacing: Theme.Spacing.xs) {
                Button { selection = store.add().id } label: { Image(systemName: "plus") }
                    .help("Add Template")
                Button {
                    if let id = selection { store.delete(id) }
                    selection = store.templates.first?.id
                } label: { Image(systemName: "minus") }
                    .disabled(selected == nil)
                    .help("Delete Template")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(Theme.Spacing.sm)
        }
    }

    // MARK: Editor

    private var editor: some View {
        Form {
            if let template = selected {
                Section("Template") {
                    TextField("Name", text: binding(template, \.name))
                    TextField("Summary", text: binding(template, \.summary), prompt: Text("feat: "))
                        .font(.monoBody)
                }
                Section("Description") {
                    TextEditor(text: binding(template, \.body))
                        .font(.system(size: 13))
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .labelsHidden()
                }
            } else {
                Text("Select a template to edit it.").foregroundStyle(Theme.textSecondary)
            }
            Section {
                Button("Restore Default Templates") {
                    store.resetToDefaults()
                    selection = store.templates.first?.id
                }
            } footer: {
                Text("Pick a template from the composer\u{2019}s template button or type / in the summary. "
                     + "A repository\u{2019}s git commit.template is offered too, and fills an empty composer.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Every edit goes through the store so it's saved straight away.
    private func binding(_ template: CommitTemplate, _ keyPath: WritableKeyPath<CommitTemplate, String>) -> Binding<String> {
        Binding(get: { store.templates.first { $0.id == template.id }?[keyPath: keyPath] ?? "" },
                set: { value in
                    guard var current = store.templates.first(where: { $0.id == template.id }) else { return }
                    current[keyPath: keyPath] = value
                    store.update(current)
                })
    }
}

#Preview {
    CommitTemplatesPreferencesTab(store: CommitTemplateStore(load: { nil }, save: { _ in }))
        .frame(width: 560, height: 520)
}
