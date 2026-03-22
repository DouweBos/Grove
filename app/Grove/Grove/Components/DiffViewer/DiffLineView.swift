// Components/DiffViewer/DiffLineView.swift
// Grove
//
// Renders a single diff line: old line number | new line number | gutter +/-
// indicator | full-width colored content.
// Monospace font, green/red backgrounds,
// word-level darker highlights, right-aligned numeric gutters.

import SwiftUI

// MARK: - DiffLineView

/// Displays one ``DiffLine`` inside a scrollable diff view.
///
/// The view is stateless — it accepts optional pre-computed attributed content
/// for word-level highlighting. When `attributedContent` is `nil`, a plain
/// colored background is used.
struct DiffLineView: View {

    // MARK: Properties

    let line: DiffLine
    /// Pre-computed word-level highlighted attributed string. Pass `nil` to
    /// render plain content (context lines, single-sided changes).
    var attributedContent: AttributedString?
    /// Whether this line is currently selected (e.g. for line-level staging).
    var isSelected: Bool = false

    // MARK: Layout constants

    private enum Layout {
        static let lineNumberWidth: CGFloat = 42
        static let gutterWidth: CGFloat = 18
        static let fontSize: CGFloat = 13
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            // Old line number
            lineNumber(line.oldLineNumber)

            // New line number
            lineNumber(line.newLineNumber)

            // +/- gutter indicator
            gutterIndicator

            // Content
            contentText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(selectionBackground)
        .contentShape(Rectangle())
    }

    // MARK: Sub-views

    private func lineNumber(_ number: Int?) -> some View {
        Group {
            if let number {
                Text(verbatim: "\(number)")
            } else {
                Text(verbatim: "")
            }
        }
        .font(.system(size: Layout.fontSize, design: .monospaced))
        .foregroundStyle(DiffColors.lineNumberForeground)
        .frame(width: Layout.lineNumberWidth, alignment: .trailing)
        .padding(.trailing, 4)
        .background(lineBackground.opacity(0.6))
    }

    private var gutterIndicator: some View {
        Text(gutterChar)
            .font(.system(size: Layout.fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(gutterColor)
            .frame(width: Layout.gutterWidth, alignment: .center)
            .background(lineBackground.opacity(0.6))
    }

    @ViewBuilder
    private var contentText: some View {
        if let attributed = attributedContent {
            Text(attributed)
                .font(.system(size: Layout.fontSize, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .background(lineBackground)
        } else {
            Text(verbatim: line.content)
                .font(.system(size: Layout.fontSize, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .background(lineBackground)
        }
    }

    // MARK: Helpers

    private var gutterChar: String {
        switch line.type {
        case .addition: return "+"
        case .deletion: return "-"
        case .context:  return " "
        }
    }

    private var gutterColor: Color {
        switch line.type {
        case .addition: return Color(red: 0x2E / 255.0, green: 0xA0 / 255.0, blue: 0x43 / 255.0)
        case .deletion: return Color(red: 0xF8 / 255.0, green: 0x51 / 255.0, blue: 0x49 / 255.0)
        case .context:  return .secondary
        }
    }

    private var lineBackground: Color {
        switch line.type {
        case .addition: return DiffColors.additionBackground
        case .deletion: return DiffColors.deletionBackground
        case .context:  return .clear
        }
    }

    private var selectionBackground: Color {
        isSelected ? Color.accentColor.opacity(0.15) : .clear
    }
}

// MARK: - Preview

#Preview("Diff Lines") {
    let deletionLine = DiffLine(
        id: "del",
        type: .deletion,
        content: "        var stagedFiles: [StatusEntry] = []",
        oldLineNumber: 13,
        newLineNumber: nil
    )
    let additionLine = DiffLine(
        id: "add",
        type: .addition,
        content: "        var status: [StatusEntry] = []",
        oldLineNumber: nil,
        newLineNumber: 13
    )
    let contextLine = DiffLine(
        id: "ctx",
        type: .context,
        content: "    @Observable",
        oldLineNumber: 10,
        newLineNumber: 10
    )
    let (delAttr, addAttr) = DiffWordHighlighter.highlight(
        deletion: deletionLine.content,
        addition: additionLine.content
    )

    return VStack(spacing: 0) {
        DiffLineView(line: contextLine)
        DiffLineView(line: deletionLine, attributedContent: delAttr)
        DiffLineView(line: additionLine, attributedContent: addAttr)
    }
    .frame(width: 600)
    .background(Color(white: 0.11))
}
