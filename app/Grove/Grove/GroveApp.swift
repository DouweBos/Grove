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
    @NSApplicationDelegateAdaptor private var appDelegate: GroveAppDelegate
    @State private var manager: RepositoryManager
    // Outlives the window, so its sessions keep fetching after a close and reopen where they were.
    @State private var windowVM: WindowViewModel

    init() {
        let manager = RepositoryManager()
        _manager = State(initialValue: manager)
        _windowVM = State(initialValue: WindowViewModel(manager: manager))
    }

    var body: some Scene {
        Window("Grove", id: "main") {
            RootWindowHost(windowVM: windowVM)
                .onAppear { AppAppearance.applyStored() }
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

/// Keeps Grove running with no window open so open repositories keep fetching in the background.
final class GroveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
