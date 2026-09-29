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
        // AppKit's restored sidebar width creeps narrower every launch, so each launch starts at the ideal width.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
        }
        // Loads the accounts now, so git's HTTPS prompts can use them from the first fetch.
        _ = HostingAccountStore.shared
    }

    var body: some Scene {
        // The value is the window's repository, so opening one already on screen brings that window forward.
        WindowGroup("Grove", id: Self.mainWindowID, for: RepositoryReference.self) { $reference in
            WindowRoot(store: windows, reference: $reference)
                .environment(windows)
                .onAppear {
                    AppAppearance.applyStored()
                    appDelegate.windows = windows
                }
        }
        .defaultSize(width: 1100, height: 700)
        // grove:// URLs go to the app delegate, which opens a tab; left to SwiftUI they'd each open a blank window too.
        .handlesExternalEvents(matching: [])
        .commands {
            GroveCommands()
            UpdateCommands(updater: updater)
            CommandLineToolCommands()
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
    /// Set by the first window; the dock menu reads recent repositories and opens windows through it.
    weak var windows: WindowStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
