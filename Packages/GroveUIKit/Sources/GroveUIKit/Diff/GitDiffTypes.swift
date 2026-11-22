// Diff/GitDiffTypes.swift
// GroveUIKit
//
// What an app passes a diff: how it's shown, what its hunks can do, and where its images come from.

#if os(macOS)
import GroveKit
import SwiftUI

/// How a diff lays out its lines; inline is the unified diff.
public nonisolated enum GitDiffLayout: String, CaseIterable, Identifiable, Hashable, Sendable {
    case inline
    case split

    public var id: Self { self }
    public var title: String { self == .inline ? "Unified" : "Split" }
    var symbol: String { self == .inline ? "text.justify.left" : "rectangle.split.2x1" }
}

public nonisolated enum GitDiffLineSide: Hashable, Sendable {
    case old
    case new
}

public nonisolated enum GitImageDiffMode: String, CaseIterable, Hashable, Sendable {
    case sideBySide = "Side by Side"
    case slider = "Slider"
    case onionSkin = "Onion Skin"
}

/// The choices every diff shares. The app keeps them, so they outlive a diff.
public struct GitDiffOptions {
    public var layout: Binding<GitDiffLayout>
    public var wrapsLines: Binding<Bool>
    public var imageMode: Binding<GitImageDiffMode>

    public init(layout: Binding<GitDiffLayout> = .constant(.inline), wrapsLines: Binding<Bool> = .constant(false),
                imageMode: Binding<GitImageDiffMode> = .constant(.sideBySide)) {
        self.layout = layout
        self.wrapsLines = wrapsLines
        self.imageMode = imageMode
    }
}

/// Hunk and line actions for one side of the working copy. Selected lines narrow a hunk's buttons to them.
public struct GitDiffStaging {
    public var side: DiffSide
    /// The lines are the selected changed ones, and empty for a whole hunk.
    public var perform: (HunkAction, HunkData, [DiffLine]) -> Void

    public init(side: DiffSide, perform: @escaping (HunkAction, HunkData, [DiffLine]) -> Void) {
        self.side = side
        self.perform = perform
    }
}

/// Which side of the working copy a pane shows, and how to switch when the file changed on both.
public struct GitDiffSideSwitch {
    public var side: DiffSide
    /// Nil shows the side without a switch.
    public var select: ((DiffSide) -> Void)?

    public init(side: DiffSide, select: ((DiffSide) -> Void)? = nil) {
        self.side = side
        self.select = select
    }
}

/// The two revisions a changeset's image files are read from.
public struct GitDiffImages {
    public var repository: any GitRepositoryProtocol
    public var old: FileRevision
    public var new: FileRevision
    /// Change it to read again, e.g. when the working tree was refreshed.
    public var reloadToken: Int

    public init(repository: any GitRepositoryProtocol, old: FileRevision, new: FileRevision, reloadToken: Int = 0) {
        self.repository = repository
        self.old = old
        self.new = new
        self.reloadToken = reloadToken
    }

    /// A commit against its first parent.
    public static func commit(_ sha: String, in repository: any GitRepositoryProtocol) -> GitDiffImages {
        GitDiffImages(repository: repository, old: .commit("\(sha)^"), new: .commit(sha))
    }
}
#endif
