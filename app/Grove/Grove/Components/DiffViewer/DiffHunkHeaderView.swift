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

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            // @@ header text
            Text(verbatim: hunk.header)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Spacer()

            // Action buttons — right-aligned
            HStack(spacing: 6) {
                if hasSelectedLines {
                    lineButtons
                }
                hunkButtons
            }
            .padding(.trailing, 8)
        }
        .background(DiffColors.hunkHeaderBackground)
    }

    // MARK: Hunk-level buttons

    @ViewBuilder
    private var hunkButtons: some View {
        if showingStaged {
            actionButton("Unstage Chunk") { onAction?(.unstageHunk) }
            actionButton("Discard Chunk", role: .destructive) { onAction?(.discardHunk) }
        } else {
            actionButton("Discard Chunk", role: .destructive) { onAction?(.discardHunk) }
            actionButton("Stage Chunk") { onAction?(.stageHunk) }
        }
    }

    // MARK: Line-level buttons

    @ViewBuilder
    private var lineButtons: some View {
        if showingStaged {
            actionButton("Unstage Lines") { onAction?(.unstageLines) }
            actionButton("Discard Lines", role: .destructive) { onAction?(.discardLines) }
        } else {
            actionButton("Discard Lines", role: .destructive) { onAction?(.discardLines) }
            actionButton("Stage Lines") { onAction?(.stageLines) }
        }
    }

    // MARK: Button Builder

    private func actionButton(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 11))
        }
        .buttonStyle(HunkActionButtonStyle(isDestructive: role == .destructive))
    }
}

// MARK: - HunkActionButtonStyle

private struct HunkActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    private let destructiveRed = Color(red: 0xF8 / 255.0, green: 0x51 / 255.0, blue: 0x49 / 255.0)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(buttonBackground(pressed: configuration.isPressed))
            )
            .foregroundStyle(isDestructive ? destructiveRed : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private func buttonBackground(pressed: Bool) -> Color {
        if isDestructive {
            return Color(red: 0xF8 / 255.0, green: 0x51 / 255.0, blue: 0x49 / 255.0)
                .opacity(pressed ? 0.25 : 0.15)
        }
        return Color(white: pressed ? 0.35 : 0.28, opacity: 1)
    }
}

// MARK: - Preview

#Preview("Hunk Header") {
    let hunk = MockData.diffResult(for: "Example.swift").hunks[0]
    VStack(spacing: 1) {
        DiffHunkHeaderView(hunk: hunk, showingStaged: false, hasSelectedLines: false) { action in
            print("Action: \(action)")
        }
        DiffHunkHeaderView(hunk: hunk, showingStaged: true, hasSelectedLines: true) { action in
            print("Action: \(action)")
        }
    }
    .frame(width: 700)
    .background(Color(white: 0.11))
}
