// Views/Settings/PreferencesView.swift
// Grove
//
// Preferences window structure with all tab panels.

import SwiftUI

// MARK: - PreferencesView

/// macOS Preferences window with an icon tab bar.
struct PreferencesView: View {

    let manager: any RepositoryManagerProtocol

    var body: some View {
        TabView {
            GeneralPreferencesTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag("general")

            AppearancePreferencesTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag("appearance")

            GitConfigPreferencesTab()
                .tabItem {
                    Label("Git Config", systemImage: "terminal")
                }
                .tag("gitconfig")

            UserProfilesPreferencesTab()
                .tabItem {
                    Label("Profiles", systemImage: "person.circle")
                }
                .tag("profiles")

            ServicesPreferencesTab()
                .tabItem {
                    Label("Services", systemImage: "network")
                }
                .tag("services")

            EditorPreferencesTab()
                .tabItem {
                    Label("Editor", systemImage: "pencil.and.outline")
                }
                .tag("editor")

            CommitTemplatesPreferencesTab()
                .tabItem {
                    Label("Templates", systemImage: "doc.text")
                }
                .tag("templates")

            KeyboardShortcutsPreferencesTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag("shortcuts")

            AdvancedPreferencesTab(manager: manager)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag("advanced")
        }
        .frame(width: 600, height: 480)
    }
}

// MARK: - GeneralPreferencesTab

/// General preferences tab.
struct GeneralPreferencesTab: View {

    @AppStorage("defaultCloneDirectory") private var defaultCloneDirectory = "~/Projects"
    @AppStorage("terminalApp") private var terminalApp = "Terminal"
    @AppStorage("autoFetchMinutes") private var autoFetchMinutes = 0
    @AppStorage("warnOnHunkDiscard") private var warnOnHunkDiscard = true
    @AppStorage("showQuickStartOnLaunch") private var showQuickStartOnLaunch = true
    @AppStorage("compactToolbar") private var compactToolbar = false
    @AppStorage("commitHistoryLimit") private var commitHistoryLimit = 500

    var body: some View {
        Form {
            Section("Repositories") {
                LabeledContent("Default clone directory") {
                    TextField("~/Projects", text: $defaultCloneDirectory)
                }
                LabeledContent("Terminal application") {
                    Picker("", selection: $terminalApp) {
                        Text("Terminal").tag("Terminal")
                        Text("iTerm").tag("iTerm")
                        Text("Warp").tag("Warp")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
            }

            Section("Fetching") {
                LabeledContent("Auto-fetch interval") {
                    Picker("", selection: $autoFetchMinutes) {
                        Text("Never").tag(0)
                        Text("Every 5 minutes").tag(5)
                        Text("Every 10 minutes").tag(10)
                        Text("Every 30 minutes").tag(30)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }

            Section("Behavior") {
                Toggle("Warn when discarding a hunk", isOn: $warnOnHunkDiscard)
                Toggle("Show Quick Start window on launch", isOn: $showQuickStartOnLaunch)
                Toggle("Compact toolbar layout", isOn: $compactToolbar)
            }

            Section("History") {
                LabeledContent("Commit history limit") {
                    TextField("500", value: $commitHistoryLimit, format: .number)
                        .frame(maxWidth: 80)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView(manager: MockRepositoryManager())
}
