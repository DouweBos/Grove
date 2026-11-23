// WorkingCopy/GitWorkingCopyHost.swift
// GroveUIKit
//
// What only the app around the working copy can do, and where its own views go.

#if os(macOS)
import GroveKit
import SwiftUI

/// Something the person did in the working copy that no view model action covers, e.g. for an app's telemetry.
public nonisolated enum GitWorkingCopyEvent: Sendable, Equatable {
    case templateInserted
    case gitmojiInserted
    case patchCreated(succeeded: Bool)
}

/// The identity profiles the composer offers; nil profiles offer no switching.
public struct GitIdentityProfiles {
    /// Read whenever the menu opens, so edits elsewhere show.
    public var load: () -> [UserProfile]
    /// Saves an identity under a label; nil offers no Save.
    public var save: ((CommitIdentity, _ label: String) -> Void)?
    public var remove: ((UserProfile) -> Void)?
    /// Opens where profiles are edited; nil offers no Manage item.
    public var manage: (() -> Void)?

    public init(load: @escaping () -> [UserProfile], save: ((CommitIdentity, String) -> Void)? = nil, remove: ((UserProfile) -> Void)? = nil,
                manage: (() -> Void)? = nil) {
        self.load = load
        self.save = save
        self.remove = remove
        self.manage = manage
    }
}

/// The app's part of the working copy. Every closure is optional; nil leaves its item out.
public struct GitWorkingCopyHost {
    /// Opens a repository-relative file, from Return, a double-click or Open File.
    public var openFile: ((String) -> Void)?
    public var profiles: GitIdentityProfiles?
    public var manageTemplates: (() -> Void)?
    /// Shows a shared dialog, e.g. Stash with some files ticked.
    public var present: ((GitDialog) -> Void)?
    public var openInDiffTool: ((StatusEntry, DiffSide) -> Void)?
    public var openInMergeTool: ((StatusEntry) -> Void)?
    /// Picks a patch to apply; nil uses an open panel.
    public var choosePatch: (() async -> URL?)?
    /// Picks where a patch is saved, from a suggested name; nil uses a save panel.
    public var choosePatchDestination: ((_ suggestedName: String, _ message: String) async -> URL?)?
    /// Whether the commit message has the caret, e.g. for the app's own Commit key.
    public var onMessageFocus: ((Bool) -> Void)?
    public var onEvent: ((GitWorkingCopyEvent) -> Void)?
    /// How the kit's diff is shown, kept by the app so it matches its other diffs; nil keeps it for the view's life.
    public var diffOptions: GitDiffOptions?
    /// The view model's error as an alert; off when the app shows it itself.
    public var showsErrors = true
    /// The composer and files column's width, kept by the app; nil keeps it for the view's life.
    public var leftWidth: Binding<Double>?
    /// The compact layout's diff height, kept by the app, 0 until dragged, which splits evenly; nil keeps it for the view's life.
    public var compactDiffHeight: Binding<Double>?
    /// Off while another view of the same view model on screen already shows its confirmations and patch sheets.
    public var presentsDialogs = true

    public init() {}
}

/// Where the app's own views go.
public struct GitWorkingCopySlots {
    /// Beside the Files header's controls, e.g. what the list covers.
    public var filesHeader: AnyView?
    /// In place of the Files header's count, e.g. how many have been viewed.
    public var filesDetail: String?
    /// At a row's trailing edge, e.g. a viewed mark.
    public var rowAccessory: ((StatusEntry) -> AnyView)?
    /// More items for a row's menu, after the kit's; gets the clicked entry and every one the menu acts on.
    public var rowMenu: ((StatusEntry, [StatusEntry]) -> AnyView)?
    /// More items for an unchanged file's menu in All Files.
    public var trackedFileMenu: ((String) -> AnyView)?
    /// Beside Commit, e.g. drafting a message.
    public var composerAccessory: AnyView?
    /// The app's diff for a file that isn't conflicted; nil shows the kit's.
    public var diff: ((StatusEntry) -> AnyView)?
    /// Shown instead of the file list and diff, e.g. another range of changes; the composer stays.
    public var replacement: (files: AnyView, detail: AnyView)?

    public init() {}
}
#endif
