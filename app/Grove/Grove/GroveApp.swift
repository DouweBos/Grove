// GroveApp.swift
// Grove
//
// Application entry point.

import SwiftUI

// MARK: - GroveApp

/// The application entry point.
///
/// One window type — each window has a tab bar where the Repositories
/// browser is a tab alongside open repo tabs.
@main
struct GroveApp: App {
    @State private var manager = RepositoryManager()

    var body: some Scene {
        Window("Grove", id: "main") {
            RootWindowHost(manager: manager)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            GroveCommands()
        }

        // Standard macOS Preferences window (Cmd+,).
        Settings {
            PreferencesView(manager: manager)
        }
    }
}
