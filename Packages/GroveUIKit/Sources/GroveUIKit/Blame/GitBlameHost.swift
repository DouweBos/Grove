// Blame/GitBlameHost.swift
// GroveUIKit
//
// What only the app around Blame can do.

#if os(macOS)
import SwiftUI

/// The app's part of Blame. Every closure is optional; nil does the kit's own or leaves the item out.
/// Opening a line in an editor goes through `GitUIHost.openFile`, offered only while blaming the working tree.
public struct GitBlameHost {
    /// Shows a picked file, or the picker again for nil, e.g. through the app's route; nil blames it in place.
    public var pick: ((_ path: String?) -> Void)?
    /// Selects a blamed commit in History; nil offers no Show Commit in History.
    public var showInHistory: ((_ sha: String) -> Void)?
    /// An icon for a file in the picker; nil shows none.
    public var fileIcon: ((_ path: String) -> AnyView)?

    public init() {}
}
#endif
