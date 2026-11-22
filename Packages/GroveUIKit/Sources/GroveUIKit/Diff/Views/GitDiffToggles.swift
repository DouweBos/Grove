// Diff/Views/GitDiffToggles.swift
// GroveUIKit
//
// How diffs are shown, as header icons: for a pane, and for an app's own header over a diff.

#if os(macOS)
import GroveKit
import SwiftUI

/// Flips line wrapping for every diff that shares the binding.
public struct GitWrapLinesToggle: View {
    private let isOn: Binding<Bool>

    public init(isOn: Binding<Bool>) {
        self.isOn = isOn
    }

    public var body: some View {
        DiffIconButton(symbol: "arrow.turn.down.left", label: "Wrap Lines",
                       help: isOn.wrappedValue ? "Don\u{2019}t Wrap Lines" : "Wrap Lines", isOn: isOn.wrappedValue) {
            isOn.wrappedValue.toggle()
        }
    }
}

/// Unified or split.
public struct GitDiffLayoutPicker: View {
    @Environment(\.gitStyle) private var style
    private let layout: Binding<GitDiffLayout>

    public init(layout: Binding<GitDiffLayout>) {
        self.layout = layout
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            ForEach(GitDiffLayout.allCases) { option in
                DiffIconButton(symbol: option.symbol, label: option.title, help: option.title,
                               isOn: option == layout.wrappedValue) {
                    if option != layout.wrappedValue { layout.wrappedValue = option }
                }
                .padding(.horizontal, 2)
                // Tint alone doesn't show the pick where the accent is the text's grey.
                .background(option == layout.wrappedValue ? style.subtleFill : .clear,
                            in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile, style: .continuous))
            }
        }
        .fixedSize()
    }
}

struct IgnoreWhitespaceToggle: View {
    let isOn: Binding<Bool>

    var body: some View {
        DiffIconButton(symbol: "text.word.spacing", label: "Ignore Whitespace",
                       help: isOn.wrappedValue ? "Show Whitespace Changes" : "Ignore Whitespace Changes", isOn: isOn.wrappedValue) {
            isOn.wrappedValue.toggle()
        }
    }
}

struct DiffOptionsMenu: View {
    @Environment(\.gitStyle) private var style
    let options: GitDiffOptions
    let ignoresWhitespace: Binding<Bool>?

    var body: some View {
        Menu {
            Picker("Layout", selection: options.layout) {
                ForEach(GitDiffLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Toggle("Wrap Lines", isOn: options.wrapsLines)
            if let ignoresWhitespace { Toggle("Ignore Whitespace", isOn: ignoresWhitespace) }
        } label: {
            Image(systemName: "ellipsis").font(style.font(13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .gitClickable()
        .fixedSize()
        .help("Diff Options")
        .accessibilityLabel("Diff Options")
    }
}

private struct DiffIconButton: View {
    @Environment(\.gitStyle) private var style
    let symbol: String
    let label: String
    let help: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(style.font(13))
                .foregroundStyle(isOn ? style.accent : style.textSecondary)
                .frame(minWidth: 16 * style.fontScale, minHeight: 22 * style.fontScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .gitClickable()
        .fixedSize()
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct DiffCounts: View {
    @Environment(\.gitStyle) private var style
    let stats: DiffStats

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            Text(verbatim: "+\(stats.additions)").foregroundStyle(style.success)
            Text(verbatim: "\u{2212}\(stats.deletions)").foregroundStyle(style.danger)
        }
        .font(style.monoCaption)
        .fixedSize()
    }
}

#Preview {
    HStack {
        GitWrapLinesToggle(isOn: .constant(true))
        GitDiffLayoutPicker(layout: .constant(.inline))
    }
    .padding()
}
#endif
