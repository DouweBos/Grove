// Views/CI/CILogRowView.swift
// Grove

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

/// One log line: its number, then the text, tinted for errors and warnings; group headers fold their lines.
struct CILogRowView: View {
    let line: CILogLine
    var isGroupExpanded = false
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
            Text(ANSIParser.strip(line.text))
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
        switch line.kind {
        case .error: Theme.dangerFill
        case .warning: Theme.bannerFill
        default: .clear
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
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
