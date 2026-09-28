// Components/DiffViewer/DiffHunkHeaderView.swift
// Grove
//
// The @@ header row for each diff hunk, with right-aligned action buttons.
// Gray background, "Discard Chunk / Stage Chunk"
// or "Discard Lines / Stage Lines" buttons aligned to the trailing edge.

import SwiftUI

// MARK: - HunkAction

/// The set of operations the user can invoke from a hunk header.
enum HunkAction {
    case stageHunk
    case unstageHunk
    case discardHunk
    case stageLines
    case unstageLines
    case discardLines
}

// MARK: - DiffHunkHeaderView

/// Gray header bar showing the raw `@@` hunk header with contextual action buttons.
///
/// Which buttons appear is controlled by `showingStaged` (whether the diff panel
/// is in Staged or Unstaged mode) and whether any lines are selected.
struct DiffHunkHeaderView: View {

    // MARK: Properties

    let hunk: HunkData
    /// True when viewing the staged diff; false for unstaged.
    let showingStaged: Bool
    /// Whether any lines inside this hunk are currently selected for line-level ops.
    var hasSelectedLines: Bool = false

    var onAction: ((HunkAction) -> Void)?

    @Environment(\.diffViewportWidth) private var viewportWidth
    @Environment(\.diffScrollOffset) private var scrollOffset

    // MARK: Body

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(verbatim: hunk.header)
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.sm)
            if onAction != nil {
                if hasSelectedLines { lineButtons }
                hunkButtons
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        // Spans the visible width and follows horizontal scrolling so the actions stay reachable.
        .frame(width: viewportWidth, height: 32)
        .background(Theme.hunkHeaderFill)
        .offset(x: scrollOffset)
    }

    // MARK: Buttons

    @ViewBuilder
    private var hunkButtons: some View {
        if showingStaged {
            actionButton("Unstage Hunk") { onAction?(.unstageHunk) }
        } else {
            actionButton("Discard Hunk", role: .destructive) { onAction?(.discardHunk) }
            actionButton("Stage Hunk") { onAction?(.stageHunk) }
        }
    }

    @ViewBuilder
    private var lineButtons: some View {
        if showingStaged {
            actionButton("Unstage Lines") { onAction?(.unstageLines) }
        } else {
            actionButton("Discard Lines", role: .destructive) { onAction?(.discardLines) }
            actionButton("Stage Lines") { onAction?(.stageLines) }
        }
    }

    private func actionButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(title, role: role, action: action)
            .buttonStyle(HunkActionButtonStyle(isDestructive: role == .destructive))
    }
}

// MARK: - HunkActionButtonStyle

private struct HunkActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isDestructive ? Theme.danger : Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(isDestructive ? Theme.dangerFill : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(isDestructive ? Color.clear : Theme.border, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Preview

#Preview("Hunk Header") {
    let hunk = MockData.diffResult(for: "Example.swift").hunks[0]
    VStack(spacing: 1) {
        DiffHunkHeaderView(hunk: hunk, showingStaged: false, hasSelectedLines: false) { _ in }
        DiffHunkHeaderView(hunk: hunk, showingStaged: true, hasSelectedLines: true) { _ in }
        DiffHunkHeaderView(hunk: hunk, showingStaged: false)
    }
    .frame(width: 700)
    .background(Theme.surface)
}
