// Diff/Table/DiffTableView.swift
// GroveUIKit
//
// A diff as an NSTableView: rows are reused and only the visible ones draw, so a 100k-line diff
// scrolls like a small one.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// What one update of the table shows.
struct DiffTableInput {
    let diff: DiffResult
    var layout: GitDiffLayout = .inline
    var wrapsLines = false
    var staging: GitDiffStaging?
    var annotations: GitDiffAnnotations?
    var style = GitUIStyle.system
    var host = GitUIHost.system
}

struct DiffTableView: NSViewRepresentable {
    let diff: DiffResult
    let layout: GitDiffLayout
    let wrapsLines: Bool
    let staging: GitDiffStaging?
    let annotations: GitDiffAnnotations?
    /// Set to be as tall as the diff inside the app's own scroll view; it hears the height.
    var onHeight: ((CGFloat) -> Void)?
    @Environment(\.gitStyle) private var style
    @Environment(\.gitHost) private var host

    func makeCoordinator() -> DiffTableCoordinator { DiffTableCoordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.makeView(fitsContent: onHeight != nil)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onHeight = onHeight
        context.coordinator.update(DiffTableInput(
            diff: diff, layout: layout, wrapsLines: wrapsLines, staging: staging,
            annotations: annotations, style: style, host: host))
    }

    static func dismantleNSView(_ view: NSView, coordinator: DiffTableCoordinator) {
        coordinator.close()
    }
}

/// The type of the diff's table, for an app's tests and drivers to find it by.
public class GitDiffTableView: NSTableView {}

enum DiffCellID {
    static let line = NSUserInterfaceItemIdentifier("GitDiffLine")
    static let header = NSUserInterfaceItemIdentifier("GitDiffHeader")
    static let annotation = NSUserInterfaceItemIdentifier("GitDiffAnnotation")
    static let row = NSUserInterfaceItemIdentifier("GitDiffRow")
}
#endif
