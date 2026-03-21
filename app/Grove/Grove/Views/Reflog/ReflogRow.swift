// Views/Reflog/ReflogRow.swift
// Grove

import SwiftUI

// MARK: - ReflogRow

/// A single row in the reflog entry list.
///
/// Displays the HEAD@{N} index, an action-type icon, the entry message,
/// and a relative date. Action types are colour-coded for quick scanning.
struct ReflogRow: View {

    let entry: ReflogEntry
    let index: Int
    let actionType: ReflogActionType

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Action icon with colour coding
            Image(systemName: actionType.systemImage)
                .foregroundStyle(actionColor)
                .font(.system(size: 14))
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                // Message (primary line)
                Text(displayMessage)
                    .font(.subheadline)
                    .lineLimit(2)
                    .truncationMode(.tail)

                // Secondary row: HEAD@{N} index + action badge + date
                HStack(spacing: 6) {
                    // HEAD@{N} label
                    Text("HEAD@{\(index)}")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)

                    // Action badge
                    Text(actionType.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(actionColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(actionColor.opacity(0.12), in: Capsule())

                    Spacer()

                    // SHA
                    Text(String(entry.newSHA.prefix(7)))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)

                    // Relative date
                    Text(entry.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    /// Strip the leading action prefix for a cleaner message display.
    private var displayMessage: String {
        let msg = entry.message
        // Messages are like "commit: feat: add foo" or "checkout: moving from A to B"
        // We trim the leading action prefix to avoid duplication with the badge.
        if let colonRange = msg.range(of: ": ") {
            return String(msg[colonRange.upperBound...])
        }
        return msg
    }

    private var actionColor: Color {
        switch actionType {
        case .commit, .commitAmend:     return .green
        case .checkout:                  return .blue
        case .rebase:                    return .orange
        case .merge:                     return .purple
        case .pull:                      return .cyan
        case .push:                      return .teal
        case .reset:                     return .red
        case .cherryPick:                return .pink
        case .other:                     return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        ForEach(Array(MockData.reflogEntries.enumerated()), id: \.element.id) { index, entry in
            ReflogRow(
                entry: entry,
                index: index,
                actionType: ReflogActionType.from(message: entry.message)
            )
        }
    }
    .listStyle(.plain)
    .frame(width: 340, height: 280)
}
