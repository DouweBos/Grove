// Views/Settings/PreferencesView.swift
// Grove
//
// Preferences window (Cmd+,). Every control here is read somewhere; see GrovePreferences.

import SwiftUI

struct PreferencesView: View {

    let manager: any RepositoryManagerProtocol
    @AppStorage(PreferencesTab.storageKey) private var tab = PreferencesTab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            GeneralPreferencesTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferencesTab.general.rawValue)
            GitConfigPreferencesTab()
                .tabItem { Label("Git", systemImage: "terminal") }
                .tag(PreferencesTab.git.rawValue)
            ProfilesPreferencesTab()
                .tabItem { Label("Profiles", systemImage: "person.2") }
                .tag(PreferencesTab.profiles.rawValue)
            SigningPreferencesTab()
                .tabItem { Label("Signing", systemImage: "signature") }
                .tag(PreferencesTab.signing.rawValue)
            ServicesPreferencesTab()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(PreferencesTab.accounts.rawValue)
            CommitTemplatesPreferencesTab()
                .tabItem { Label("Templates", systemImage: "text.badge.plus") }
                .tag(PreferencesTab.templates.rawValue)
            EditorPreferencesTab()
                .tabItem { Label("Tools", systemImage: "hammer") }
                .tag(PreferencesTab.tools.rawValue)
            AdvancedPreferencesTab(manager: manager)
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(PreferencesTab.advanced.rawValue)
        }
        .frame(width: 560, height: 520)
    }
}

/// Preferences tabs, so other windows can open Preferences on the one they need.
enum PreferencesTab: String {
    case general, git, profiles, signing, accounts, templates, tools, advanced

    static let storageKey = "preferencesTab"

    @MainActor
    func open(_ openSettings: OpenSettingsAction) {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
        openSettings()
    }
}

// MARK: - General

struct GeneralPreferencesTab: View {

    @AppStorage(GrovePreferences.Key.appearance) private var appearance = GrovePreferences.Default.appearance
    @AppStorage(GrovePreferences.Key.defaultCloneDirectory) private var defaultCloneDirectory = "~/Projects"
    @AppStorage(GrovePreferences.Key.terminalApp) private var terminalApp = GrovePreferences.Default.terminalApp
    @AppStorage(GrovePreferences.Key.autoFetchMinutes) private var autoFetchMinutes = GrovePreferences.Default.autoFetchMinutes
    @AppStorage(GrovePreferences.Key.warnOnHunkDiscard) private var warnOnHunkDiscard = GrovePreferences.Default.warnOnHunkDiscard
    @AppStorage(GrovePreferences.Key.staleBranchDays) private var staleBranchDays = GrovePreferences.Default.staleBranchDays
    @AppStorage(GrovePreferences.Key.receivesBetaUpdates) private var receivesBetaUpdates = false
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, _ in AppAppearance.applyStored() }
            }

            Section("Repositories") {
                LabeledContent("Clone into") {
                    HStack {
                        TextField("Clone into", text: $defaultCloneDirectory, prompt: Text("~/Projects"))
                            .labelsHidden()
                            .font(.monoCaption)
                        Button("Choose\u{2026}", action: chooseCloneDirectory)
                    }
                }
                Picker("Terminal", selection: $terminalApp) {
                    ForEach(TerminalApp.allCases) { app in
                        Text(app.isInstalled ? app.rawValue : "\(app.rawValue) (not installed)").tag(app.rawValue)
                    }
                }
            }

            Section {
                Picker("Fetch remotes automatically", selection: $autoFetchMinutes) {
                    Text("Off").tag(0)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                }
            } header: {
                Text("Fetching")
            } footer: {
                Text("Runs in the background for open repositories. Takes effect immediately.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            Section("Safety") {
                Toggle("Confirm before discarding a hunk or lines", isOn: $warnOnHunkDiscard)
            }

            Section("Branches Review") {
                Stepper("Stale after \(staleBranchDays) days without commits", value: $staleBranchDays, in: 7...365, step: 7)
            }

            Section {
                Toggle("Receive beta updates", isOn: $receivesBetaUpdates)
                Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text(AppUpdater.isEnabled ? "Grove checks for updates daily." : "Development builds don't update.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseCloneDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (defaultCloneDirectory as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            defaultCloneDirectory = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

#Preview {
    PreferencesView(manager: MockRepositoryManager())
        .environment(AppUpdater())
}
