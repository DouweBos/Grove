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
    @State private var clearBeforeImport = false

    private var towerInstalled: Bool { TowerImporter.isTowerInstalled }

    var body: some View {
        Form {
            towerImportSection
            dataManagementSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Tower Import

    @ViewBuilder
    private var towerImportSection: some View {
        Section {
            if towerInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import your repository bookmarks and groups from Tower into Grove.")
                        .foregroundStyle(.secondary)

                    Toggle("Clear existing Grove data before import", isOn: $clearBeforeImport)

                    switch importState {
                    case .idle:
                        EmptyView()

                    case .importing:
                        ProgressView()
                            .controlSize(.small)

                    case .success(let groupCount, let bookmarkCount, let skippedCount):
                        Label(
                            "Imported \(groupCount) groups and \(bookmarkCount) repositories"
                                + (skippedCount > 0 ? " (\(skippedCount) skipped — path not found)" : ""),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)

                    case .error(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)

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

    // MARK: - Actions

    private func performImport() {
        importState = .importing
        do {
            let result = try TowerImporter.importBookmarks()
            manager.importData(
                groups: result.groups,
                bookmarks: result.bookmarks,
                clearFirst: clearBeforeImport
            )
            importState = .success(
                groups: result.groups.count,
                bookmarks: result.bookmarks.count,
                skipped: result.skippedPaths.count
            )
        } catch {
            importState = .error(error.localizedDescription)
        }
    }

    // MARK: - State

    private enum ImportState: Equatable {
        case idle
        case importing
        case success(groups: Int, bookmarks: Int, skipped: Int)
        case error(String)
    }
}

// MARK: - Preview

#Preview {
    AdvancedPreferencesTab(manager: MockRepositoryManager())
}
