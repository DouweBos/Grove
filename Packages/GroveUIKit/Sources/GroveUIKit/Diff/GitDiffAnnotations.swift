// Diff/GitDiffAnnotations.swift
// GroveUIKit
//
// The app's own rows under a diff's lines, and how a new one starts: from the gutter's + or the menu.

#if os(macOS)
import GroveKit
import SwiftUI

public nonisolated struct GitDiffLineAnchor: Hashable, Sendable {
    public var hunk: Int
    /// An index into the hunk's lines.
    public var line: Int

    public init(hunk: Int, line: Int) {
        self.hunk = hunk
        self.line = line
    }
}

/// The lines an annotation starts from.
public struct GitDiffPickedLines {
    /// The file of the diff they were picked in, which can still be the last one while the next loads.
    public let filePath: String
    public let hunk: HunkData
    /// Indices into `hunk.lines`.
    public let indices: [Int]
    /// The side of a split diff they were picked on; nil in the unified one.
    public let side: GitDiffLineSide?
}

public struct GitDiffAnnotationContext {
    /// The width the row has for its card.
    public let width: CGFloat
    let present: (@escaping (_ close: @escaping () -> Void) -> AnyView) -> Void

    /// Shows content in a popover over the row, e.g. its editor.
    public func presentPopover(_ content: @escaping (_ close: @escaping () -> Void) -> some View) {
        present { AnyView(content($0)) }
    }
}

public struct GitDiffAnnotation: Identifiable {
    public let id: String
    let side: GitDiffLineSide?
    let revision: AnyHashable
    let anchor: (DiffResult) -> GitDiffLineAnchor?
    let height: (CGFloat) -> CGFloat
    let content: (GitDiffAnnotationContext) -> AnyView

    /// - Parameters:
    ///   - side: The side of a split diff the row sits on.
    ///   - revision: Change it when the content, the height or the anchor changes.
    ///   - anchor: The line it hangs under; nil hides it. Asked only when the diff or the annotations change.
    ///   - height: Its height at a card width, without laying it out: the table asks first.
    ///   - content: AppKit hosts it, so it brings the app's environment values it needs.
    public init(id: String, side: GitDiffLineSide?, revision: AnyHashable,
                anchor: @escaping (DiffResult) -> GitDiffLineAnchor?, height: @escaping (_ width: CGFloat) -> CGFloat,
                @ViewBuilder content: @escaping (GitDiffAnnotationContext) -> some View) {
        self.id = id
        self.side = side
        self.revision = revision
        self.anchor = anchor
        self.height = height
        self.content = { AnyView(content($0)) }
    }
}

public struct GitDiffAnnotations {
    let items: [GitDiffAnnotation]
    let addTitle: String
    let maxWidth: CGFloat
    let composer: (GitDiffPickedLines, @escaping () -> Void) -> AnyView?

    /// - Parameters:
    ///   - addTitle: The menu item that starts one.
    ///   - maxWidth: The widest a card gets; a narrower pane narrows it.
    ///   - composer: What the + and the menu show in a popover; nil when these lines can't take one.
    public init(_ items: [GitDiffAnnotation], addTitle: String, maxWidth: CGFloat = 520,
                composer: @escaping (_ lines: GitDiffPickedLines, _ close: @escaping () -> Void) -> AnyView?) {
        self.items = items
        self.addTitle = addTitle
        self.maxWidth = maxWidth
        self.composer = composer
    }
}
#endif
