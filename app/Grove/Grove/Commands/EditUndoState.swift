// Commands/EditUndoState.swift
// Grove
//
// Observable mirror of the key window's responder-chain undo state, so the
// Edit menu can choose between text undo and git undo.

import AppKit
import Observation

/// Snapshot of the responder chain's `UndoManager`, refreshed after every event.
///
/// AppKit undo state isn't observable, so this re-reads it on each
/// `NSWindow.didUpdateNotification` and only writes when a value changes.
@MainActor
@Observable
final class EditUndoState {

    static let shared = EditUndoState()

    /// True while a text view (e.g. the commit message field editor) is first responder.
    private(set) var isEditingText = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoTitle = "Undo"
    private(set) var redoTitle = "Redo"

    /// The open repository's git stack while the main window is key (nil in Preferences).
    /// Registered explicitly because `focusedSceneValue` drops out after sheets close.
    var gitUndo: GitUndoManager? { isRepositoryWindowKey ? repositoryUndo : nil }
    private var repositoryUndo: GitUndoManager?
    private var isRepositoryWindowKey = false

    /// Set by a git action until the user types again; text history from before it is dropped.
    @ObservationIgnored private var textHistoryIsStale = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { EditUndoState.shared.refresh() }
        }
    }

    func refresh() {
        let responder = NSApp.keyWindow?.firstResponder
        let manager = responder?.undoManager
        if textHistoryIsStale, responder is NSText, let manager {
            // User typing registers a named action ("Typing"); SwiftUI emptying the commit
            // field after the git action registers an unnamed one, which is dropped.
            if manager.canUndo, !manager.undoActionName.isEmpty {
                textHistoryIsStale = false
            } else {
                manager.removeAllActions()
            }
        }
        update(\.isRepositoryWindowKey, NSApp.keyWindow?.identifier?.rawValue.hasPrefix(Self.mainWindowID) ?? false)
        update(\.isEditingText, responder is NSText)
        update(\.canUndo, manager?.canUndo ?? false)
        update(\.canRedo, manager?.canRedo ?? false)
        update(\.undoTitle, manager?.undoMenuItemTitle ?? "Undo")
        update(\.redoTitle, manager?.redoMenuItemTitle ?? "Redo")
    }

    /// SwiftUI names each window of the `main` WindowGroup after its scene id.
    static let mainWindowID = GroveApp.mainWindowID

    func attach(_ manager: GitUndoManager?) {
        repositoryUndo = manager
    }

    /// A git action is newer than any typing (a commit even clears the message it
    /// typed), so Cmd+Z should reach git rather than restore stale text.
    func gitActionRecorded() {
        textHistoryIsStale = true
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
            responder.undoManager?.removeAllActions()
        }
        refresh()
    }

    /// Sends `undo:`/`redo:` down the key window's responder chain.
    func forward(undo: Bool) {
        NSApp.sendAction(Selector((undo ? "undo:" : "redo:")), to: nil, from: nil)
    }

    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<EditUndoState, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
