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
        static let lineNumberWidth: CGFloat = 40
        static let gutterWidth: CGFloat = 16
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)
            Text(gutterChar)
                .foregroundStyle(gutterColor)
                .frame(width: Layout.gutterWidth, alignment: .center)
            contentText
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, Theme.Spacing.lg)
        }
        .font(.monoBody)
        .padding(.vertical, 1)
        .background(lineBackground)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(Theme.accent).frame(width: 3) }
        }
        .background(isSelected ? Theme.selectionFill : .clear)
        .contentShape(Rectangle())
    }

    // MARK: Sub-views

    private func lineNumber(_ number: Int?) -> some View {
        Text(verbatim: number.map(String.init) ?? "")
            .foregroundStyle(Theme.textSecondary)
            .frame(width: Layout.lineNumberWidth, alignment: .trailing)
            .padding(.trailing, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var contentText: some View {
        if let attributed = attributedContent {
            Text(attributed)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        } else {
            Text(verbatim: line.content)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
    }

    // MARK: Helpers

    private var gutterChar: String {
        switch line.type {
        case .addition: return "+"
        case .deletion: return "−"
        case .context:  return " "
        }
    }

    private var gutterColor: Color {
        switch line.type {
        case .addition: return Theme.added
        case .deletion: return Theme.deleted
        case .context:  return Theme.textSecondary
        }
    }

    private var lineBackground: Color {
        switch line.type {
        case .addition: return Theme.addedFill
        case .deletion: return Theme.deletedFill
        case .context:  return .clear
        }
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
    .background(Theme.surface)
}
