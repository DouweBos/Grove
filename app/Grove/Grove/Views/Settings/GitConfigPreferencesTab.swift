// Views/Settings/GitConfigPreferencesTab.swift
// Grove
//
// Global git config (`git config --global`), written only when the user clicks Save.

import SwiftUI

@MainActor
@Observable
final class GlobalGitConfigModel {

    /// Keys this tab edits; booleans are stored as "true"/"false", empty means unset.
    static let keys = ["user.name", "user.email", "core.editor", "init.defaultBranch",
                       "pull.rebase", "push.autoSetupRemote", "fetch.prune"]

    private(set) var saved: [String: String] = [:]
    private(set) var draft: [String: String] = [:]
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    var hasChanges: Bool { saved != draft }

    /// Honors GIT_CONFIG_GLOBAL so tests can point at a scratch file.
    var configFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["GIT_CONFIG_GLOBAL"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gitconfig")
    }

    private let shell = GitShell(workingDirectory: FileManager.default.homeDirectoryForCurrentUser)

    func load() async {
        var values: [String: String] = [:]
        for key in Self.keys {
            let result = try? await shell.runAllowingFailure(["config", "--global", "--get", key])
            if let result, result.isSuccess {
                values[key] = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        saved = values
        draft = values
    }

    func value(_ key: String) -> String { draft[key] ?? "" }
    func bool(_ key: String) -> Bool { value(key).lowercased() == "true" }

    func set(_ key: String, _ value: String) {
        draft[key] = value.isEmpty ? nil : value
        didSave = false
    }

    func setBool(_ key: String, _ on: Bool) {
        // Turning off a key that was never set leaves it unset rather than writing "false".
        set(key, on ? "true" : (saved[key] == nil ? "" : "false"))
    }

    func revert() {
        draft = saved
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            for key in Self.keys where draft[key] != saved[key] {
                let value = draft[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if value.isEmpty {
                    let result = try await shell.runAllowingFailure(["config", "--global", "--unset", key])
                    guard result.isSuccess || result.exitCode == 5 else {
                        throw GitShellError.nonZeroExit(command: "config", exitCode: result.exitCode, stderr: result.stderr)
                    }
                } else {
                    try await shell.run(["config", "--global", key, value])
                }
            }
            errorMessage = nil
            await load()
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}

struct GitConfigPreferencesTab: View {

    @State private var model = GlobalGitConfigModel()

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: binding("user.name"), prompt: Text("Your Name"))
                TextField("Email", text: binding("user.email"), prompt: Text("you@example.com"))
            }
            Section("Defaults") {
                TextField("Editor (core.editor)", text: binding("core.editor"), prompt: Text("vim"))
                TextField("Initial branch", text: binding("init.defaultBranch"), prompt: Text("master"))
            }
            Section("Pull, Push & Fetch") {
                Toggle("Rebase when pulling", isOn: boolBinding("pull.rebase"))
                Toggle("Set upstream automatically on first push", isOn: boolBinding("push.autoSetupRemote"))
                Toggle("Prune deleted remote branches when fetching", isOn: boolBinding("fetch.prune"))
            }
            Section {
                LabeledContent("File") {
                    Text(model.configFileURL.path).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(Theme.danger)
                }
                HStack {
                    Button("Open in Editor") { try? ExternalToolLauncher.openInEditor([model.configFileURL]) }
                    Spacer()
                    if model.didSave && !model.hasChanges {
                        Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    }
                    Button("Revert") { model.revert() }.disabled(!model.hasChanges)
                    Button("Save") { Task { await model.save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.hasChanges || model.isSaving)
                }
            } footer: {
                Text("Changes apply to every repository without its own override, and are written only when you click Save.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.load() }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { model.value(key) }, set: { model.set(key, $0) })
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { model.bool(key) }, set: { model.setBool(key, $0) })
    }
}

#Preview {
    GitConfigPreferencesTab().frame(width: 520, height: 560)
}
