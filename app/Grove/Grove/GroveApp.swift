// GroveApp.swift
// Grove
//
// Application entry point — WS2 owns this file in Phase B.
// WS5 will take ownership in Phase C to wire in the real GitKit engine
// and replace MockRepositoryManager with RepositoryManager.

import SwiftUI

// MARK: - GroveApp

/// The application entry point.
///
/// Declares two scenes:
/// - A singleton `Window` for the repository browser (which navigates in-place to open repositories).
/// - A `Settings` scene for the macOS Preferences window.
@main
struct GroveApp: App {

    // MARK: State

    /// Shared repository manager — used by both the browser window and Settings.
    @State private var manager = RepositoryManager()

    // MARK: Body

    var body: some Scene {
        // Singleton repository browser window (Cmd+Shift+1 to bring to front).
        Window("Grove", id: "repositories") {
            RepositoryBrowserRootView(manager: manager)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            GroveCommands()
        }

        // Standard macOS Preferences window (Cmd+,).
        Settings {
            PreferencesView(manager: manager)
        }
    }
}

// MARK: - RepositoryBrowserRootView

/// Wrapper that creates a stable `RepositoryBrowserViewModel` for the browser window.
///
/// Keeping the ViewModel in `@State` ensures it persists for the lifetime
/// of the browser window and is not re-created on every body evaluation.
///
/// Uses `RepositoryManager` backed by UserDefaults for real bookmark persistence.
/// `MockRepositoryManager` is still used in SwiftUI previews.
private struct RepositoryBrowserRootView: View {

    let manager: any RepositoryManagerProtocol

    @State private var viewModel: RepositoryBrowserViewModel

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
        self._viewModel = State(initialValue: RepositoryBrowserViewModel(manager: manager))
    }

    var body: some View {
        Group {
            if let reference = viewModel.openedReference {
                RepositoryWindowView(reference: reference)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                viewModel.closeRepository()
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .help("Back to Repositories")
                        }
                    }
            } else {
                RepositoryBrowserView()
                    .environment(viewModel)
            }
        }
    }
}
