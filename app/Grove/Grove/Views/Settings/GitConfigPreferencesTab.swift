// Views/Settings/GitConfigPreferencesTab.swift
// Grove
//
// Git configuration preferences: global identity, editor, merge/diff tools, pull behavior.

import SwiftUI

// MARK: - GitConfigPreferencesTab

/// Preferences tab exposing frequently used global git config settings.
struct GitConfigPreferencesTab: View {

    // MARK: - Identity

    @State private var userName = ""
    @State private var userEmail = ""

    // MARK: - Tools

    @State private var coreEditor: CoreEditor = .vim
    @State private var mergeTool: MergeTool = .opendiff
    @State private var diffTool: DiffTool = .opendiff

    // MARK: - Pull / Push Behavior

    @State private var pullRebase = false
    @State private var pushAutoSetupRemote = false

    var body: some View {
        Form {
            identitySection
            toolsSection
            behaviorSection
            rawConfigSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Identity Section

    @ViewBuilder
    private var identitySection: some View {
        Section("Identity") {
            LabeledContent("Name") {
                TextField("Your Name", text: $userName)
            }
            LabeledContent("Email") {
                TextField("you@example.com", text: $userEmail)
                    .textContentType(.emailAddress)
            }
        }
    }

    // MARK: - Tools Section

    @ViewBuilder
    private var toolsSection: some View {
        Section("Tools") {
            LabeledContent("Core editor") {
                Picker("", selection: $coreEditor) {
                    ForEach(CoreEditor.allCases) { editor in
                        Text(editor.label).tag(editor)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            LabeledContent("Merge tool") {
                Picker("", selection: $mergeTool) {
                    ForEach(MergeTool.allCases) { tool in
                        Text(tool.label).tag(tool)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            LabeledContent("Diff tool") {
                Picker("", selection: $diffTool) {
                    ForEach(DiffTool.allCases) { tool in
                        Text(tool.label).tag(tool)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: - Behavior Section

    @ViewBuilder
    private var behaviorSection: some View {
        Section("Pull & Push") {
            Toggle("Rebase instead of merge on pull (pull.rebase)", isOn: $pullRebase)
            Toggle("Auto-setup remote on push (push.autoSetupRemote)", isOn: $pushAutoSetupRemote)
        }
    }

    // MARK: - Raw Config Section

    @ViewBuilder
    private var rawConfigSection: some View {
        Section("Raw Config") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Open the global .gitconfig file in your default external editor.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Button("Edit .gitconfig") {
                    openGitConfig()
                }
            }
        }
    }

    // MARK: - Actions

    private func openGitConfig() {
        let url = URL(fileURLWithPath: NSString("~/.gitconfig").expandingTildeInPath)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Supporting Types

extension GitConfigPreferencesTab {

    enum CoreEditor: String, CaseIterable, Identifiable {
        case vim, nano, emacs, vscode, xcode

        var id: String { rawValue }

        var label: String {
            switch self {
            case .vim: return "Vim"
            case .nano: return "Nano"
            case .emacs: return "Emacs"
            case .vscode: return "VS Code"
            case .xcode: return "Xcode"
            }
        }
    }

    enum MergeTool: String, CaseIterable, Identifiable {
        case opendiff, kaleidoscope, vimdiff, meld, beyond

        var id: String { rawValue }

        var label: String {
            switch self {
            case .opendiff: return "opendiff (FileMerge)"
            case .kaleidoscope: return "Kaleidoscope"
            case .vimdiff: return "vimdiff"
            case .meld: return "Meld"
            case .beyond: return "Beyond Compare"
            }
        }
    }

    enum DiffTool: String, CaseIterable, Identifiable {
        case opendiff, kaleidoscope, vimdiff, meld, beyond

        var id: String { rawValue }

        var label: String {
            switch self {
            case .opendiff: return "opendiff (FileMerge)"
            case .kaleidoscope: return "Kaleidoscope"
            case .vimdiff: return "vimdiff"
            case .meld: return "Meld"
            case .beyond: return "Beyond Compare"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    GitConfigPreferencesTab()
        .frame(width: 540, height: 440)
}
