// Views/Root/DockMenu.swift
// Grove
//
// The dock icon's right-click menu: recently opened repositories, then clone and new window.

import AppKit

extension GroveAppDelegate {
    static let dockRecentLimit = 10

    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let windows else { return nil }
        let menu = NSMenu()
        let recents = windows.manager.bookmarks
            .compactMap { bookmark in bookmark.displayLastOpenedDate.map { (bookmark, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(Self.dockRecentLimit)
        for (bookmark, _) in recents {
            let item = ClosureMenuItem(title: bookmark.displayName) {
                RepositoryURLRouter.openHandler?(bookmark.path)
            }
            item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            menu.addItem(item)
        }
        if !recents.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem(title: "Clone Repository\u{2026}") { windows.perform(.cloneRepository) })
        menu.addItem(ClosureMenuItem(title: "New Window") {
            NSApp.activate()
            WindowStore.newWindowHandler?()
        })
        return menu
    }
}

/// A menu item that runs a closure, since the dock menu has no responder chain to target.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @objc private func run() { handler() }
}
