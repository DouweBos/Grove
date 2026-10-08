// Views/Settings/AdvancedPreferencesTab.swift
// Grove
//
// Advanced preferences tab with Tower data import and data management.

import SwiftUI

// MARK: - AdvancedPreferencesTab

/// Advanced settings tab with Tower import and data management.
struct AdvancedPreferencesTab: View {

    let manager: any RepositoryManagerProtocol

    @State private var importState: ImportState = .idle
    @State private var showClearConfirmation = false
    @State private var showResetConfirmation = false
    @State private var clearBeforeImport = false
    @State private var environment = GitEnvironment.customVariables(.global)

    private var towerInstalled: Bool { TowerImporter.isTowerInstalled }

    var body: some View {
        Form {
            environmentSection
            CommandLineToolSection()
            towerImportSection
            dataManagementSection
            resetToDefaultsSection
        }
        .formStyle(.grouped)
        .onChange(of: environment) { _, variables in GitEnvironment.setCustomVariables(variables, .global) }
    }

    // MARK: - Environment

    private var environmentSection: some View {
        Section {
            EnvironmentVariablesEditor(variables: $environment)
        } header: {
            Text("Environment Variables")
        } footer: {
            Text("Passed to every git command Grove runs, and so to hooks. A repository's own variables, set in its Settings, "
                 + "take precedence.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Tower Import

    @ViewBuilder
    private var towerImportSection: some View {
        Section {
            if towerInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import your repository bookmarks, groups and service accounts from Tower into Grove. "
                         + "macOS may ask before Grove reads Tower\u{2019}s account tokens from the Keychain.")
                        .foregroundStyle(Theme.textSecondary)

                    Toggle("Clear existing Grove data before import", isOn: $clearBeforeImport)

                    switch importState {
                    case .idle:
                        EmptyView()

                    case .importing:
                        ProgressView()
                            .controlSize(.small)

                    case .success(let groupCount, let bookmarkCount, let skippedCount, let accounts):
                        Label(
                            "Imported \(groupCount) groups, \(bookmarkCount) repositories and \(accounts.imported) accounts"
                                + (skippedCount > 0 ? " (\(skippedCount) skipped — path not found)" : ""),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(Theme.success)
                        ForEach(accounts.failures, id: \.self) { failure in
                            Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                        }

                    case .error(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    }

                    HStack {
                        Button("Import from Tower") {
                            performImport()
                        }
                        .disabled(importState == .importing)
                    }
                }
            } else {
                Label(
                    "Tower is not installed. Install Tower or ensure its data exists at ~/Library/Application Support/com.fournova.Tower3/",
                    systemImage: "info.circle"
                )
                .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Tower Import")
        }
    }

    // MARK: - Data Management

    @ViewBuilder
    private var dataManagementSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remove all repository bookmarks and groups from Grove. This does not delete any repositories from disk.")
                    .foregroundStyle(Theme.textSecondary)

                Button("Clear All Data", role: .destructive) {
                    showClearConfirmation = true
                }
                .confirmationDialog(
                    "Clear all Grove data?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All Data", role: .destructive) {
                        manager.clearAllData()
                        importState = .idle
                    }
                } message: {
                    Text("This will remove all repository bookmarks and groups from Grove. Your repositories on disk will not be affected.")
                }
            }
        } header: {
            Text("Data Management")
        }
    }

    // MARK: - Reset to Defaults

    @ViewBuilder
    private var resetToDefaultsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reset all preferences to their default values. This does not affect your repository bookmarks.")
                    .foregroundStyle(Theme.textSecondary)

                Button("Reset to Defaults", role: .destructive) {
                    showResetConfirmation = true
                }
                .confirmationDialog(
                    "Reset all preferences to defaults?",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset to Defaults", role: .destructive) {
                        resetAllPreferences()
                    }
                } message: {
                    Text("All settings will be restored to their default values.")
                }
            }
        } header: {
            Text("Preferences")
        }
    }

    private func resetAllPreferences() {
        GrovePreferences.resetAll()
    }

    // MARK: - Actions

    private func performImport() {
        importState = .importing
        let result: TowerImporter.ImportResult
        do {
            result = try TowerImporter.importBookmarks()
        } catch {
            importState = .error(error.localizedDescription)
            return
        }
        manager.importData(groups: result.groups, bookmarks: result.bookmarks, clearFirst: clearBeforeImport)
        Task {
            let accounts = await TowerAccountImport.migrate(TowerAccountImport.accounts(), into: .shared)
            importState = .success(groups: result.groups.count, bookmarks: result.bookmarks.count,
                                   skipped: result.skippedPaths.count, accounts: accounts)
        }
    }

    // MARK: - State

    private enum ImportState: Equatable {
        case idle
        case importing
        case success(groups: Int, bookmarks: Int, skipped: Int, accounts: TowerAccountImport.Outcome)
        case error(String)
    }
}

// MARK: - Preview

#Preview {
    AdvancedPreferencesTab(manager: MockRepositoryManager())
}
