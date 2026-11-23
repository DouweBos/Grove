// WorkingCopy/WorkingCopyCompact.swift
// GroveUIKit
//
// The working copy for narrow places: the file list over the selected file's diff, split by a draggable gap,
// under the composer when there is one.

#if os(macOS)
import GroveKit
import SwiftUI

struct WorkingCopyCompact: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.workingCopyHost) private var host
    let showsComposer: Bool
    @State private var ownHeight: Double = 0
    @State private var dragStartHeight: Double?

    static let minList: Double = 100
    static let minDiff: Double = 160

    var body: some View {
        VStack(spacing: GitMetrics.Spacing.md) {
            WorkingCopyComposerArea(showsComposer: showsComposer)
            GeometryReader { geo in
                VStack(spacing: 0) {
                    WorkingCopyFiles().frame(maxHeight: .infinity)
                    resizeHandle(total: geo.size.height)
                    WorkingCopyDetailArea().frame(height: clampedDiffHeight(total: geo.size.height))
                }
            }
        }
    }

    /// The diff's height: what was dragged to, or half before any drag, leaving the list its minimum.
    static func diffHeight(stored: Double, total: Double, fontScale: Double) -> Double {
        let stored = stored > 0 ? stored : (total - Double(GitMetrics.Spacing.md)) / 2
        let lower = minDiff * fontScale
        let upper = max(lower, total - minList * fontScale - Double(GitMetrics.Spacing.md))
        return min(max(stored, lower), upper)
    }

    private var diffHeight: Double {
        get { host.compactDiffHeight?.wrappedValue ?? ownHeight }
        nonmutating set {
            if let binding = host.compactDiffHeight { binding.wrappedValue = newValue } else { ownHeight = newValue }
        }
    }

    private func clampedDiffHeight(total: CGFloat) -> CGFloat {
        CGFloat(Self.diffHeight(stored: diffHeight, total: Double(total), fontScale: style.fontScale))
    }

    private func resizeHandle(total: CGFloat) -> some View {
        Color.clear
            .frame(height: GitMetrics.Spacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartHeight ?? Double(clampedDiffHeight(total: total))
                        dragStartHeight = start
                        diffHeight = start - value.translation.height
                    }
                    .onEnded { _ in
                        diffHeight = Double(clampedDiffHeight(total: total))
                        dragStartHeight = nil
                    }
            )
            .accessibilityHidden(true)
    }
}
#endif
