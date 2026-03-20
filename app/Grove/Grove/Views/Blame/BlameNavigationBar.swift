// Views/Blame/BlameNavigationBar.swift
// Grove

import SwiftUI

// MARK: - BlameNavigationBar

/// Navigation bar displayed at the top of ``BlameView``.
///
/// Shows:
/// - The blamed file's path (truncated from the start to preserve the filename).
/// - The current revision label (short SHA or "HEAD").
/// - **Prev** button to step back through the file's history.
/// - **Current** button to jump back to HEAD.
struct BlameNavigationBar: View {

    // MARK: - Properties

    /// The file path displayed in the centre of the bar.
    let filePath: String

    /// Short identifier for the current revision, or `nil` when at HEAD.
    let revision: String?

    /// Whether the Prev button should be enabled.
    let canNavigateToPrevious: Bool

    /// Whether the Current button should be enabled (i.e. not already at HEAD).
    let canNavigateToCurrent: Bool

    /// Called when the user taps **Prev**.
    var onPrevious: (() -> Void)?

    /// Called when the user taps **Current**.
    var onCurrent: (() -> Void)?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {

            // File path — truncate from the start so the filename always shows.
            Text(filePath)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .truncationMode(.head)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Revision badge
            revisionBadge

            Divider()
                .frame(height: 16)

            // Navigation buttons
            Button("Prev") {
                onPrevious?()
            }
            .disabled(!canNavigateToPrevious)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Current") {
                onCurrent?()
            }
            .disabled(!canNavigateToCurrent)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var revisionBadge: some View {
        let label = revision.map { String($0.prefix(7)) } ?? "HEAD"
        Text(label)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        BlameNavigationBar(
            filePath: "Sources/Grove/Views/WorkingCopy/WorkingCopyView.swift",
            revision: "a1b2c3d4e5f6",
            canNavigateToPrevious: true,
            canNavigateToCurrent: true,
            onPrevious: { },
            onCurrent: { }
        )

        BlameNavigationBar(
            filePath: "Sources/Grove/Domain/AppState.swift",
            revision: nil,
            canNavigateToPrevious: true,
            canNavigateToCurrent: false,
            onPrevious: { },
            onCurrent: { }
        )
    }
    .frame(width: 700)
}
