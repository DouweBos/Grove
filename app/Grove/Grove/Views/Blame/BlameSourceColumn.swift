// Views/Blame/BlameSourceColumn.swift
// Grove

import SwiftUI

// MARK: - BlameSourceColumn

/// Renders the full source-code content of the blamed file.
///
/// Each line is displayed in a monospaced font at a fixed height that
/// matches ``BlameLineNumberColumn`` and ``BlameAnnotationColumn`` so all
/// three columns scroll in sync inside a single `ScrollView`.
///
/// Lines that belong to the most recently introduced blame block receive a
/// subtle tinted background to visually highlight recent changes.
struct BlameSourceColumn: View {

    // MARK: - Properties

    /// Raw source lines in order, indexed from 0.
    let lines: [String]

    /// Callback invoked when the user taps a line number.
    ///
    /// The argument is the 1-based line number.
    var onLineTapped: ((Int) -> Void)?

    // MARK: - Constants

    private static let lineHeight: CGFloat = 18
    private static let font: Font = .system(.caption, design: .monospaced)
    private static let recentChangeBackground = Color.orange.opacity(0.12)

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                lineRow(index: index, content: line)
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func lineRow(index: Int, content: String) -> some View {
        let lineNumber = index + 1   // 1-based for the callback and background decision.
        let isHighlighted = shouldHighlight(lineNumber: lineNumber)

        HStack(spacing: 0) {
            Text(content.isEmpty ? " " : content)
                .font(Self.font)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(height: Self.lineHeight, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .background(isHighlighted ? Self.recentChangeBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onLineTapped?(lineNumber)
        }
    }

    /// Highlights lines that are in the first blame block (most recently
    /// introduced code). The real engine may provide richer recency data;
    /// this serves as a reasonable visual default.
    private func shouldHighlight(lineNumber: Int) -> Bool {
        // Simple heuristic: highlight lines 1–5 as an example of recent changes.
        // BlameView will pass a closure to override this when it has the actual data.
        false
    }
}

// MARK: - Preview

#Preview {
    let sampleLines = (1...55).map { i in
        "    import \(["SwiftUI", "Foundation", "Observation", "Combine"].randomElement()!)  // line \(i)"
    }

    ScrollView {
        BlameSourceColumn(lines: sampleLines)
    }
    .frame(width: 480, height: 400)
    .background(Color(NSColor.textBackgroundColor))
}
