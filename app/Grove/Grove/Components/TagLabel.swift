// Components/TagLabel.swift
// Grove
//
// A colored pill label for Git tags shown inline on commit rows.
// Styled after BranchLabel but uses a gold/yellow tint and a tag icon.

import SwiftUI

// MARK: - TagLabel

/// A compact pill label for Git tags, using a gold tint to differentiate
/// from branch labels (which use green/blue).
///
/// Mirrors the layout of ``BranchLabel`` so both can appear side-by-side on
/// commit rows without visual inconsistency.
///
/// Usage:
/// ```swift
/// TagLabel(name: "v2.1.0")
/// TagLabel(tag: tagInfo)
/// ```
struct TagLabel: View {

    // MARK: Properties

    let name: String

    // MARK: Body

    var body: some View {
        Label(name, systemImage: "tag.fill")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
    }

    // MARK: Private — Colors

    /// Gold tint that reads clearly in both light and dark mode.
    private var foregroundColor: Color {
        Color(red: 0xD2 / 255, green: 0x8B / 255, blue: 0x00 / 255)
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.18)
    }
}

// MARK: - Convenience Init

extension TagLabel {

    /// Creates a label from a ``TagInfo`` value.
    init(tag: TagInfo) {
        self.name = tag.name
    }
}

// MARK: - Preview

#Preview("Tag Labels") {
    HStack(spacing: 8) {
        TagLabel(name: "v1.0.0")
        TagLabel(name: "v2.1.0-beta")
        TagLabel(name: "release/2024.1")
        // Side-by-side with branch labels to verify visual harmony
        BranchLabel(name: "main", kind: .localBranch(isHEAD: true))
        BranchLabel(name: "origin/main", kind: .remoteBranch)
    }
    .padding()
}
