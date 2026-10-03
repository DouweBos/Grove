// Views/CI/CILogRowView.swift
// Grove

import GroveKit
import SwiftUI

/// A step's header in the log: opens and closes the step's lines.
struct CILogStepHeader: View {
    let section: CILogSection
    let isExpanded: Bool
    let onToggle: () -> Void

    @Environment(\.diffViewportWidth) private var viewportWidth
    @Environment(\.diffScrollOffset) private var scrollOffset

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(section.lines.isEmpty ? 0 : 1)
                    .frame(width: 12)
                if let step = section.step {
                    CIStepRow(step: step)
                } else {
                    Text(section.title).font(.rowTitle)
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, Theme.Spacing.md)
            // Clear of a legacy scroll bar, which covers the viewport's edge.
            .padding(.trailing, Theme.Spacing.xl)
            // Spans the visible width and follows horizontal scrolling, like a diff's hunk header.
            .frame(width: viewportWidth, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: scrollOffset)
        .accessibilityLabel("\(section.title), \(section.step?.status.title ?? "")")
    }
}

/// One log line: its number, then the text in its terminal colors, tinted for errors and warnings; group headers fold their lines.
struct CILogRowView: View {
    let line: CILogLine
    var isGroupExpanded = false
    var searchText = ""
    var isCurrentMatch = false
    var onToggleGroup: () -> Void = {}

    @Environment(\.diffViewportWidth) private var viewportWidth
    @Environment(\.diffScrollOffset) private var scrollOffset

    static let numberWidth: CGFloat = 44
    static let gutterWidth = numberWidth + Theme.Spacing.md + 14

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: "\(line.number)")
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .frame(width: Self.numberWidth, alignment: .trailing)
                    .padding(.trailing, Theme.Spacing.md)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(isGroupExpanded ? 90 : 0))
                    .opacity(line.kind == .group ? 1 : 0)
                    .frame(width: 14, alignment: .leading)
            }
            // Pinned while the text scrolls sideways underneath.
            .padding(.vertical, 1)
            .background(fill)
            .background(Theme.surface)
            .offset(x: scrollOffset)
            .zIndex(1)
            Text(CILogText.attributed(line.text, searchText: searchText))
                .foregroundStyle(textColor)
                .fontWeight(line.kind == .group ? .semibold : .regular)
                .textSelection(.enabled)
                .fixedSize(horizontal: viewportWidth != nil, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, Theme.Spacing.lg)
                .padding(.leading, line.group == nil ? 0 : Theme.Spacing.md)
                .padding(.vertical, 1)
        }
        .font(.monoBody)
        .background(fill)
        .contentShape(Rectangle())
        .onTapGesture { if line.kind == .group { onToggleGroup() } }
    }

    private var textColor: Color {
        switch line.kind {
        case .error: Theme.danger
        case .warning: Theme.warning
        case .notice: Theme.info
        case .command: Theme.info
        case .debug: Theme.textSecondary
        case .plain, .group: Theme.textPrimary
        }
    }

    private var fill: Color {
        if isCurrentMatch { return Theme.selectionFill }
        switch line.kind {
        case .error: return Theme.dangerFill
        case .warning: return Theme.bannerFill
        default: return .clear
        }
    }
}

/// A log line's text with its terminal styles, and search matches marked.
enum CILogText {

    static func attributed(_ text: String, searchText: String = "") -> AttributedString {
        var result = AttributedString()
        for span in ANSIParser.spans(text) {
            var run = AttributedString(span.text)
            if let color = span.color { run.foregroundColor = color.themeColor }
            if span.isBold || span.isItalic {
                let weighted = Font.monoBody.weight(span.isBold ? .bold : .regular)
                run.font = span.isItalic ? weighted.italic() : weighted
            }
            if span.isUnderlined { run.underlineStyle = .single }
            result += run
        }
        guard !searchText.isEmpty else { return result }
        var searched = result.startIndex..<result.endIndex
        while let match = result[searched].range(of: searchText, options: .caseInsensitive) {
            result[match].backgroundColor = Theme.searchMatchFill
            searched = match.upperBound..<result.endIndex
        }
        return result
    }
}

extension ANSIColor {
    /// Terminal colors in the app's palette; black and white follow the appearance so neither disappears.
    var themeColor: Color {
        switch self {
        case .black: Theme.textSecondary
        case .red: Theme.danger
        case .green: Theme.success
        case .yellow: Theme.warning
        case .blue: Theme.info
        case .magenta: Theme.ansiMagenta
        case .cyan: Theme.ansiCyan
        case .white: Theme.textPrimary
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        CILogRowView(line: CILogLine(id: 9, number: 0, text: "\u{1B}[32m✔\u{1B}[0m \u{1B}[1mDiffParserTests\u{1B}[0m \u{1B}[36mpassed\u{1B}[0m",
                                     kind: .plain, group: nil), searchText: "parser")
        CILogRowView(line: CILogLine(id: 0, number: 1, text: "Run swift test", kind: .group, group: nil), isGroupExpanded: true)
        CILogRowView(line: CILogLine(id: 1, number: 2, text: "shell: /bin/bash -e {0}", kind: .plain, group: 0))
        CILogRowView(line: CILogLine(id: 2, number: 3, text: "Compiling GroveApp.swift", kind: .plain, group: nil))
        CILogRowView(line: CILogLine(id: 3, number: 4, text: "Variable was never mutated", kind: .warning, group: nil))
        CILogRowView(line: CILogLine(id: 4, number: 5, text: "Process completed with exit code 65.", kind: .error, group: nil))
    }
    .frame(width: 520)
    .padding(.vertical)
    .background(Theme.surface)
}
