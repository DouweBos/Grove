// Views/Root/WindowRoot.swift
// Grove

import SwiftUI

/// Claims a window's model from the store when it opens and hands it back when it closes.
struct WindowRoot: View {
    let store: WindowStore
    /// The window's repository; kept current so restoration and "open in new window" find it.
    @Binding var reference: RepositoryReference?

    @State private var windowVM: WindowViewModel?
    @State private var handlesLaunchArguments = false
    @State private var hostWindow = HostWindow()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let windowVM {
                RootWindowHost(windowVM: windowVM, handlesLaunchArguments: handlesLaunchArguments)
                    .onChange(of: windowVM.openRepo) { _, repo in reference = repo }
                    .onChange(of: windowVM.isKeyWindow) { _, isKey in if isKey { store.windowBecameKey(windowVM) } }
            } else {
                Theme.background
            }
        }
        .toastOverlay()
        .background(WindowTabbingAccessor(store: store) { hostWindow.window = $0 })
        .onAppear {
            WindowStore.newTabHandler = { [store, openWindow] in
                store.requestTab()
                openWindow(id: GroveApp.mainWindowID)
            }
            WindowStore.newWindowHandler = { [openWindow] in openWindow(id: GroveApp.mainWindowID) }
            WindowStore.openTabHandler = { [store, openWindow] reference in
                store.requestTab()
                openWindow(id: GroveApp.mainWindowID, value: reference)
            }
            RepositoryURLRouter.openHandler = { [store, openWindow] path in
                // Opened from Terminal, Grove may not be active, so there's no key window to join.
                store.requestTab(in: NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.tabbingIdentifier == WindowStore.tabbingIdentifier })
                openWindow(id: GroveApp.mainWindowID, value: RepositoryReference(path: path))
                NSApp.activate()
            }
            // A tabbed window's content can disappear and come back without the window closing.
            if let windowVM { return store.windowReappeared(windowVM) }
            handlesLaunchArguments = store.consumeLaunchArguments()
            let claimed = store.claimWindow(opening: reference)
            claimed.closeWindow = { [hostWindow] in hostWindow.window?.close() }
            windowVM = claimed
            reference = claimed.openRepo
        }
        .onDisappear {
            if let windowVM { store.windowClosed(windowVM) }
        }
    }
}
