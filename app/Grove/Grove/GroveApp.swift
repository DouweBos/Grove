// GroveApp.swift
// Grove
//
// Application entry point.

import SwiftUI

// MARK: - GroveApp

/// The application entry point: any number of windows, each browsing or showing one repository.
@main
struct GroveApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor private var appDelegate: GroveAppDelegate
    @State private var manager: RepositoryManager
    // Outlives windows, so closed ones keep fetching and the next window reopens where the last left off.
    @State private var windows: WindowStore
    @State private var updater = AppUpdater()

    init() {
        let manager = RepositoryManager()
        _manager = State(initialValue: manager)
        _windows = State(initialValue: WindowStore(manager: manager))
    }

    var body: some Scene {
        // The value is the window's repository, so opening one already on screen brings that window forward.
        WindowGroup("Grove", id: Self.mainWindowID, for: RepositoryReference.self) { $reference in
            WindowRoot(store: windows, reference: $reference)
                .environment(windows)
                .onAppear { AppAppearance.applyStored() }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            GroveCommands()
            UpdateCommands(updater: updater)
        }

        // Standard macOS Preferences window (Cmd+,).
        Settings {
            PreferencesView(manager: manager)
                .environment(updater)
        }
    }
}

/// Keeps Grove running with no window open so open repositories keep fetching in the background.
final class GroveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
