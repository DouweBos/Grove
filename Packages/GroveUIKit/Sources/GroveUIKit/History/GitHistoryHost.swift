// History/GitHistoryHost.swift
// GroveUIKit
//
// What only the app around History, Compare and File History can do.

#if os(macOS)
import GroveKit
import SwiftUI

/// The app's part of History. Every closure is optional; nil shows the kit's own or leaves the item out.
/// Blame at a revision goes through the view model's `onOpenBlame`, conflicts through its `onRebaseStopped`.
public struct GitHistoryHost {
    /// The list's title in place of the branch's name, e.g. what a session's branch is compared with.
    public var title: String?
    /// Commits shown at full strength, e.g. a branch's own over its base's; the rest are dimmed. Nil dims none.
    public var ownCommits: Set<String>?
    /// Opens a comparison of two refs; nil shows the kit's sheet.
    public var compare: ((_ base: String, _ compare: String) -> Void)?
    /// Plans an interactive rebase from a commit; nil shows the kit's sheet.
    public var interactiveRebase: ((CommitInfo) -> Void)?
    /// Selects a compared commit in History; nil offers no Show in History.
    public var showInHistory: ((_ sha: String) -> Void)?
    /// An author's picture for an email at a pixel size; nil shows initials.
    public var avatarURL: ((_ email: String, _ pixels: Int) -> URL?)?
    /// How the kit's diffs show, kept by the app so they match its others; nil keeps them for the view's life.
    public var diffOptions: GitDiffOptions?
    /// Opens Blame for a compared file at the compared ref; nil offers none. History's own goes through `onOpenBlame`.
    public var openBlame: ((_ path: String, _ revision: String) -> Void)?
    /// The app's rows under a compared file's lines, e.g. review comments.
    public var compareAnnotations: ((_ path: String, _ base: String, _ compare: String) -> GitDiffAnnotations?)?

    public init() {}
}

extension EnvironmentValues {
    @Entry var historyHost = GitHistoryHost()
}
#endif
