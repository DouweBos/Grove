// Views/Settings/PreferencesView.swift
// Grove
//
// Preferences window structure. WS7 will fill in each tab panel.
// This file establishes the TabView shell that WS7 populates.

import SwiftUI

// MARK: - PreferencesView

/// macOS Preferences window with an icon tab bar.
///
/// Tab panels are currently placeholders — WS7 will implement them.
struct PreferencesView: View {

    let manager: any RepositoryManagerProtocol

    var body: some View {
        TabView {
            GeneralPreferencesTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag("general")

            Text("Appearance preferences — WS7 will implement")
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag("appearance")

            Text("Git Config preferences — WS7 will implement")
                .tabItem {
                    Label("Git Config", systemImage: "terminal")
                }
                .tag("gitconfig")

            Text("User Profiles preferences — WS7 will implement")
                .tabItem {
                    Label("Profiles", systemImage: "person.circle")
                }
                .tag("profiles")

            Text("Services preferences — WS7 will implement")
                .tabItem {
                    Label("Services", systemImage: "network")
                }
                .tag("services")

            AdvancedPreferencesTab(manager: manager)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag("advanced")
        }
        .frame(width: 540, height: 440)
    }
}

// MARK: - GeneralPreferencesTab

/// General preferences tab.
struct GeneralPreferencesTab: View {

    @State private var defaultCloneDirectory = "~/Projects"
    @State private var terminalApp = "Terminal"
    @State private var autoFetchMinutes = 0
    @State private var warnOnChunkDiscard = true
    @State private var showQuickStartOnLaunch = true
    @State private var compactToolbar = false
    @State private var commitHistoryLimit = 500

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
                Toggle("Warn when discarding a chunk", isOn: $warnOnChunkDiscard)
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
