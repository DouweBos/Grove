// Views/Settings/EditorPreferencesTab.swift
// Grove
//
// External apps: editor for "Open in Editor", diff and merge tools for conflicts.

import SwiftUI

struct EditorPreferencesTab: View {

    @AppStorage(GrovePreferences.Key.externalEditor) private var editorRaw = GrovePreferences.Default.externalEditor
    @AppStorage(GrovePreferences.Key.externalEditorPath) private var editorPath = ""
    @AppStorage(GrovePreferences.Key.diffToolPath) private var diffToolPath = ""
    @AppStorage(GrovePreferences.Key.diffToolArguments) private var diffToolArguments = "$LOCAL $REMOTE"
    @AppStorage(GrovePreferences.Key.mergeToolPath) private var mergeToolPath = ""
    @AppStorage(GrovePreferences.Key.mergeToolArguments) private var mergeToolArguments = "$LOCAL $REMOTE $BASE $MERGED"

    private var editor: ExternalEditor { ExternalEditor(rawValue: editorRaw) ?? .systemDefault }

    var body: some View {
        Form {
            Section {
                Picker("Open files with", selection: $editorRaw) {
                    ForEach(ExternalEditor.allCases) { option in
                        Text(option.isInstalled ? option.rawValue : "\(option.rawValue) (not installed)")
                            .tag(option.rawValue)
                    }
                }
                if editor == .custom {
                    pathField("Application or executable", text: $editorPath, placeholder: "/Applications/MyEditor.app")
                }
            } header: {
                Text("Editor")
            } footer: {
                Text("Used by Open in Editor in Quick Actions and Repository Settings.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            Section {
                pathField("Tool", text: $diffToolPath, placeholder: "/usr/bin/opendiff")
                TextField("Arguments", text: $diffToolArguments).font(.monoCaption)
            } header: {
                Text("Diff Tool")
            } footer: {
                tokens("$LOCAL old version, $REMOTE new version. Leave the tool empty to use FileMerge.")
            }

            Section {
                pathField("Tool", text: $mergeToolPath, placeholder: "/usr/bin/opendiff")
                TextField("Arguments", text: $mergeToolArguments).font(.monoCaption)
            } header: {
                Text("Merge Tool")
            } footer: {
                tokens("$LOCAL ours, $REMOTE theirs, $BASE common ancestor, $MERGED output. Used from the conflict wizard.")
            }
        }
        .formStyle(.grouped)
    }

    private func pathField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            TextField(title, text: text, prompt: Text(placeholder)).font(.monoCaption)
            Button("Choose\u{2026}") { choosePath(into: text) }
        }
    }

    private func tokens(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
    }

    private func choosePath(into binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
}

#Preview {
    EditorPreferencesTab().frame(width: 520, height: 560)
}
