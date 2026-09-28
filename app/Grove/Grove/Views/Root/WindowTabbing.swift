// Views/Root/WindowTabbing.swift
// Grove
//
// Native window tabs: a window opened as a tab joins the window it was requested from.

import AppKit
import SwiftUI

extension WindowStore {
    /// Grove windows only tab with each other, not with Preferences.
    static let tabbingIdentifier = "grove-main"
}

/// Hands the hosting NSWindow to the store once it exists, so it can join a tab group.
struct WindowTabbingAccessor: NSViewRepresentable {
    let store: WindowStore

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.onWindow = { store.attach($0) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AccessorView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let onWindow else { return }
            self.onWindow = nil
            onWindow(window)
        }
    }
}

/// The tab bar's + button sends `newWindowForTab:` down the responder chain, ending at the app delegate.
extension GroveAppDelegate {
    @objc func newWindowForTab(_ sender: Any?) {
        WindowStore.newTabHandler?()
    }
}
