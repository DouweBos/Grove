// GroveApp.swift
// Grove
//
// Application entry point.

import SwiftUI
import SwiftData

// MARK: - GroveApp

/// The application entry point.
///
/// One window type — each window has a tab bar where the Repositories
/// browser is a tab alongside open repo tabs.
@main
struct GroveApp: App {

    // MARK: SwiftData Container

    private let container: ModelContainer = {
        let schema = Schema([
            RepositoryBookmark.self,
            RepositoryGroup.self,
            UserProfile.self,
            CommitTemplate.self,
            GitServiceAccount.self,
            AppPreferences.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: fallbackConfig)
        }
    }()

    // MARK: State

    @State private var manager: RepositoryManager

    // MARK: Init

    init() {
        let context = container.mainContext
        _manager = State(initialValue: RepositoryManager(context: context))
    }

    // MARK: Body

    var body: some Scene {
        // Single window — starts showing the Repositories browser tab.
        // Opening repos adds tabs in the same window.
        Window("Grove", id: "main") {
            RepositoryWindowHost(manager: manager)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            GroveCommands()
        }
        .modelContainer(container)

        // Standard macOS Preferences window (Cmd+,).
        Settings {
            PreferencesView(manager: manager)
        }
        .modelContainer(container)
    }
}
