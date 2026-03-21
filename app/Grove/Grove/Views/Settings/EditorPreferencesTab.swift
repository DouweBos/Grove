// Views/Settings/EditorPreferencesTab.swift
// Grove
//
// Editor preferences: external editor, diff tool, and merge tool integration.

import SwiftUI

// MARK: - EditorPreferencesTab

/// Preferences tab for configuring external editor and diff/merge tool integration.
struct EditorPreferencesTab: View {

    // MARK: - External Editor

    @AppStorage("externalEditorName") private var defaultEditorRaw: String = ExternalEditor.vscode.rawValue

    private var defaultEditor: ExternalEditor {
        ExternalEditor(rawValue: defaultEditorRaw) ?? .vscode
    }

    // MARK: - Diff Tool

    @AppStorage("externalDiffToolPath")       private var externalDiffToolPath = ""
    @AppStorage("externalDiffToolArguments")  private var diffToolArguments = "$LOCAL $REMOTE"

    // MARK: - Merge Tool

    @AppStorage("externalMergeToolPath")      private var externalMergeToolPath = ""
    @AppStorage("externalMergeToolArguments") private var mergeToolArguments = "$LOCAL $REMOTE $BASE $MERGED"

    // MARK: - Editor Path

    @AppStorage("externalEditorPath") private var editorPath = ""

    var body: some View {
        Form {
            editorSection
            diffToolSection
            mergeToolSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Editor Section

    @ViewBuilder
    private var editorSection: some View {
        Section("External Editor") {
            LabeledContent("Default editor") {
                Picker("", selection: $defaultEditorRaw) {
                    ForEach(ExternalEditor.allCases) { editor in
                        Text(editor.label).tag(editor.rawValue)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            HStack {
                Text("Opens files via Grove's \"Open in Editor\" action and the \u{2318}\u{21E7}E shortcut.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            }
        }
    }

    // MARK: - Diff Tool Section

    @ViewBuilder
    private var diffToolSection: some View {
        Section("External Diff Tool") {
            LabeledContent("Tool path") {
                HStack {
                    TextField("/usr/bin/opendiff", text: $externalDiffToolPath)
                        .font(.system(.body, design: .monospaced))
                    Button("Browse…") {
                        browseForPath(binding: $externalDiffToolPath)
                    }
                }
            }

            LabeledContent("Arguments") {
                TextField("$LOCAL $REMOTE", text: $diffToolArguments)
                    .font(.system(.body, design: .monospaced))
            }

            ArgumentsHelpText(tokens: [("$LOCAL", "left/old version"), ("$REMOTE", "right/new version")])
        }
    }

    // MARK: - Merge Tool Section

    @ViewBuilder
    private var mergeToolSection: some View {
        Section("External Merge Tool") {
            LabeledContent("Tool path") {
                HStack {
                    TextField("/usr/bin/opendiff", text: $externalMergeToolPath)
                        .font(.system(.body, design: .monospaced))
                    Button("Browse…") {
                        browseForPath(binding: $externalMergeToolPath)
                    }
                }
            }

            LabeledContent("Arguments") {
                TextField("$LOCAL $REMOTE $BASE $MERGED", text: $mergeToolArguments)
                    .font(.system(.body, design: .monospaced))
            }

            ArgumentsHelpText(tokens: [
                ("$LOCAL", "current branch version"),
                ("$REMOTE", "incoming version"),
                ("$BASE", "common ancestor"),
                ("$MERGED", "output file path")
            ])
        }
    }

    // MARK: - Actions

    private func browseForPath(binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select Executable"
        panel.directoryURL = URL(fileURLWithPath: "/usr/bin")
        if panel.runModal() == .OK {
            binding.wrappedValue = panel.url?.path ?? binding.wrappedValue
        }
    }
}

// MARK: - ArgumentsHelpText

/// Inline token reference displayed beneath an arguments text field.
private struct ArgumentsHelpText: View {
    let tokens: [(token: String, description: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tokens, id: \.token) { pair in
                HStack(spacing: 4) {
                    Text(pair.token)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("—")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(pair.description)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Supporting Types

extension EditorPreferencesTab {

    enum ExternalEditor: String, CaseIterable, Identifiable {
        case vscode = "VS Code"
        case sublime = "Sublime Text"
        case xcode = "Xcode"
        case bbedit = "BBEdit"
        case nova = "Nova"
        case textmate = "TextMate"
        case vim = "Vim (Terminal)"
        case custom = "Custom…"

        var id: String { rawValue }
        var label: String { rawValue }
    }
}

// MARK: - Preview

#Preview {
    EditorPreferencesTab()
        .frame(width: 540, height: 440)
}
