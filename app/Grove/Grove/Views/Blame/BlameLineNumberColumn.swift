// Views/Blame/BlameLineNumberColumn.swift
// Grove

import SwiftUI

// MARK: - BlameLineNumberColumn

/// Renders a right-aligned, fixed-width column of line numbers.
///
/// Numbers are styled in secondary gray to recede visually behind the
/// source code column while remaining readable at all font sizes.
struct BlameLineNumberColumn: View {

    // MARK: - Properties

    /// Total number of source lines to display numbers for.
    let lineCount: Int

    // MARK: - Constants

    private static let lineHeight: CGFloat = 18
    private static let font: Font = .system(.caption, design: .monospaced)
    private static let textColor: Color = .secondary

    // MARK: - Body

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...max(1, lineCount), id: \.self) { number in
                Text("\(number)")
                    .font(Self.font)
                    .foregroundStyle(Self.textColor)
                    .frame(height: Self.lineHeight, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        BlameLineNumberColumn(lineCount: 55)
    }
    .frame(width: 60, height: 400)
    .background(Color(NSColor.textBackgroundColor))
}
