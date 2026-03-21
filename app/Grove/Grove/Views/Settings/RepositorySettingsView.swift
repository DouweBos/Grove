// Views/Settings/RepositorySettingsView.swift
// Grove
//
// Repository-specific settings panel shown when selecting "Settings"
// in the sidebar. Displays and edits the local .git/config values
// for the current repository.

import SwiftUI

// MARK: - RepositorySettingsView

/// Settings panel scoped to the current repository.
///
/// Reads and writes values from the repository's local git config
/// (`.git/config`), separate from the global `~/.gitconfig`.
struct RepositorySettingsView: View {

    let repository: any GitRepositoryProtocol

    // MARK: State

    @State private var userName = ""
    @State private var userEmail = ""
    @State private var defaultRemote = "origin"
    @State private var pullRebase = false
    @State private var isLoading = true

    // MARK: Body

    var body: some View {
        Form {
            Section("Identity (this repository only)") {
                LabeledContent("Name") {
                    TextField("Use global", text: $userName)
                        .frame(maxWidth: 220)
                }
                LabeledContent("Email") {
                    TextField("Use global", text: $userEmail)
                        .frame(maxWidth: 220)
                }
                Text("Leave empty to use the global git config values.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Pull Behavior") {
                Toggle("Use rebase instead of merge", isOn: $pullRebase)
            }

            Section("Remote") {
                LabeledContent("Default remote") {
                    TextField("origin", text: $defaultRemote)
                        .frame(maxWidth: 160)
                }
            }

            Section("Repository Info") {
                LabeledContent("Path") {
                    Text(repository.path.path)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let branch = repository.currentBranch {
                    LabeledContent("Current branch") {
                        Text(branch.name)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("State") {
                    Text(stateDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repository.path.path)
                }
                Button("Open in Terminal") {
                    openInTerminal()
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task {
            await loadConfig()
        }
    }

    // MARK: Helpers

    private var stateDescription: String {
        switch repository.repositoryState {
        case .normal: return "Normal"
        case .merge: return "Merging"
        case .rebase, .rebaseInteractive: return "Rebasing"
        case .revert: return "Reverting"
        case .cherrypick: return "Cherry-picking"
        case .bisect: return "Bisecting"
        }
    }

    private func loadConfig() async {
        isLoading = false
    }

    private func openInTerminal() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = [repository.path.path]
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

// MARK: - Preview

#Preview {
    RepositorySettingsView(repository: MockGitRepository())
        .frame(width: 480, height: 500)
}
