// Diff/Views/GitDiffView.swift
// GroveUIKit
//
// A file's text diff, or what stands in for one: binary, a Git LFS pointer, nothing to show.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitDiffView: View {
    @Environment(\.gitStyle) private var style
    private let diff: DiffResult
    private let options: GitDiffOptions
    private let staging: GitDiffStaging?
    private let annotations: GitDiffAnnotations?
    private let fitsContent: Bool
    /// The pointer change shown as text, by its hunk.
    @State private var shownPointer: String?

    /// - Parameters:
    ///   - staging: What its hunks can do; nil shows no buttons.
    ///   - annotations: The app's rows under lines, e.g. review comments.
    ///   - fitsContent: As tall as the diff, for inside the app's own vertical scroll view.
    ///     Only what's on screen is laid out.
    public init(diff: DiffResult, options: GitDiffOptions = GitDiffOptions(), staging: GitDiffStaging? = nil,
                annotations: GitDiffAnnotations? = nil, fitsContent: Bool = false) {
        self.diff = diff
        self.options = options
        self.staging = staging
        self.annotations = annotations
        self.fitsContent = fitsContent
    }

    public var body: some View {
        if diff.isBinary {
            GitEmptyState(systemImage: "doc.zipper", title: "Binary File", subtitle: "Diff is not available for binary files.")
        } else if let pointers = pointerChange, shownPointer != diff.hunks.first?.id {
            LFSPointerDiffView(old: pointers.old, new: pointers.new) { shownPointer = diff.hunks.first?.id }
        } else if diff.hunks.isEmpty {
            GitEmptyState(systemImage: "checkmark.circle", title: "No Changes",
                          subtitle: diff.oldPath != nil ? "Renamed without content changes." : "Only mode or whitespace changes.")
        } else if fitsContent {
            FittedDiff(diff: diff, options: options, staging: staging, annotations: annotations)
        } else {
            DiffTableView(diff: diff, layout: options.layout.wrappedValue, wrapsLines: options.wrapsLines.wrappedValue,
                          staging: staging, annotations: annotations)
        }
    }

    /// A pointer is three lines, so a real diff is never read through for one.
    private var pointerChange: (old: LFSPointer?, new: LFSPointer?)? {
        guard diff.hunks.count == 1, diff.hunks[0].lines.count <= 16 else { return nil }
        return LFSPointer.sides(of: diff)
    }
}

/// As tall as the table says, and until it has, as tall as unwrapped lines.
private struct FittedDiff: View {
    @Environment(\.gitStyle) private var style
    let diff: DiffResult
    let options: GitDiffOptions
    let staging: GitDiffStaging?
    let annotations: GitDiffAnnotations?
    @State private var height: CGFloat?

    var body: some View {
        DiffTableView(diff: diff, layout: options.layout.wrappedValue, wrapsLines: options.wrapsLines.wrappedValue,
                      staging: staging, annotations: annotations, onHeight: { height = $0 })
            .frame(height: height ?? estimatedHeight)
    }

    private var estimatedHeight: CGFloat {
        let lines = diff.hunks.reduce(0) { $0 + $1.lines.count }
        return (CGFloat(lines) * 17 + CGFloat(diff.hunks.count) * 32) * style.fontScale
    }
}

#Preview {
    GitDiffView(diff: MockData.diffResult(for: "WorkingCopyViewModel.swift"),
                staging: GitDiffStaging(side: .unstaged) { _, _, _ in })
        .frame(width: 700, height: 500)
        .background(GitUIStyle.system.surface)
}
#endif
