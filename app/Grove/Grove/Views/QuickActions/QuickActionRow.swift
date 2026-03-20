// Views/QuickActions/QuickActionRow.swift
// Grove

import SwiftUI

// MARK: - QuickActionRow

/// A single result row inside the Quick Actions panel.
///
/// Layout:
/// ```
/// [ icon ]  Title (primary)           [type label]  [Move to Front]
///           subtitle (secondary)
/// ```
///
/// When `isSelected` is true the row receives the accent-colour highlight.
struct QuickActionRow: View {

    // MARK: - Properties

    let result: QuickActionResult
    let isSelected: Bool

    /// Called when the user clicks "Move to Front" (pin to top).
    var onMoveToFront: (() -> Void)?

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 10) {

            // Kind icon
            Image(systemName: result.kind.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : Color.accentColor)
                .frame(width: 20, alignment: .center)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Trailing secondary controls (only visible on selected row)
            if isSelected {
                HStack(spacing: 6) {
                    // Type label pill
                    Text(result.kind.typeLabel)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)

                    // Move to Front action
                    Button("Move to Front") {
                        onMoveToFront?()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.white)
                }
            } else {
                // Type label (non-selected, muted)
                Text(result.kind.typeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? Color.accentColor
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Preview

#Preview {
    let branch = MockData.branches[0]
    let commit = MockData.commits[0]

    VStack(spacing: 2) {
        QuickActionRow(
            result: .navigation(item: .workingCopy, title: "Working Copy"),
            isSelected: true,
            onMoveToFront: { }
        )
        QuickActionRow(
            result: .navigation(item: .history, title: "History"),
            isSelected: false
        )
        QuickActionRow(
            result: .branch(branch),
            isSelected: false
        )
        QuickActionRow(
            result: .commit(commit),
            isSelected: false
        )
    }
    .padding(8)
    .frame(width: 480)
    .background(Color(NSColor.windowBackgroundColor))
}
