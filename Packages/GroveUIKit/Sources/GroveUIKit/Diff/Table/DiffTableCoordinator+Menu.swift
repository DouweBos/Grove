// Diff/Table/DiffTableCoordinator+Menu.swift
// GroveUIKit

#if os(macOS)
import AppKit
import GroveKit

extension DiffTableCoordinator: NSMenuDelegate {

    private final class HunkPayload: NSObject {
        let action: HunkAction
        let hunk: Int
        let id: String
        let side: DiffSide

        init(action: HunkAction, hunk: Int, id: String, side: DiffSide) {
            self.action = action
            self.hunk = hunk
            self.id = id
            self.side = side
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let table else { return }
        fill(menu, clickedRow: table.clickedRow)
    }

    func fill(_ menu: NSMenu, clickedRow clicked: Int) {
        menu.removeAllItems()
        guard let table, let diff else { return }
        if rows.indices.contains(clicked), rows[clicked].kind.isSelectable, textSelection?.row != clicked,
           !table.selectedRowIndexes.contains(clicked) {
            table.selectRowIndexes([clicked], byExtendingSelection: false)
        }
        let copy = NSMenuItem(title: "Copy", action: #selector(DiffNSTableView.copy(_:)), keyEquivalent: "")
        copy.target = table
        menu.addItem(copy)
        guard rows.indices.contains(clicked) else { return }
        if let annotations, side(row: clicked, x: 0) != nil || side(row: clicked, x: geometry.half) != nil {
            let add = NSMenuItem(title: annotations.addTitle, action: #selector(addFromMenu(_:)), keyEquivalent: "")
            add.target = self
            add.tag = clicked
            menu.insertItem(add, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        if host.openFile != nil, let line = newLine(at: clicked) {
            let open = NSMenuItem(title: "Open in Editor at Line", action: #selector(openAtLine(_:)), keyEquivalent: "")
            open.target = self
            open.tag = line
            open.representedObject = diff.filePath
            menu.insertItem(open, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        guard let staging else { return }
        let hunk = rows[clicked].hunk
        // Selected lines narrow the header's buttons; the whole hunk stays a right-click away.
        let groups = hasSelectedChanges(inHunk: hunk) ? [lineButtons, hunkButtons] : [hunkButtons]
        for group in groups {
            menu.addItem(.separator())
            for button in group.reversed() {
                let item = NSMenuItem(title: button.title, action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = HunkPayload(action: button.action, hunk: hunk, id: diff.hunks[hunk].id, side: staging.side)
                menu.addItem(item)
            }
        }
    }

    @objc private func openAtLine(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        host.openFile?(path, sender.tag)
    }

    @objc private func addFromMenu(_ sender: NSMenuItem) {
        let side = hover?.row == sender.tag ? hover?.side ?? .whole : .whole
        startAnnotation(row: sender.tag, side: side)
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? HunkPayload, payload.side == staging?.side else { return }
        perform(payload.action, hunk: payload.hunk, id: payload.id)
    }
}
#endif
