// Composer/GitmojiPicker.swift
// GroveUIKit
//
// Searchable gitmoji list shown from the commit composer; picking one prefixes the summary.

#if os(macOS)
import GroveKit
import SwiftUI

struct GitmojiPicker: View {
    @Environment(\.gitStyle) private var style
    let onPick: (Gitmoji) -> Void

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var results: [Gitmoji] { Gitmoji.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            GitSearchField(placeholder: "Search gitmoji", text: query, onChange: { query = $0 }, focus: $isSearchFocused)
                .padding(GitMetrics.Spacing.sm)
                .onSubmit { if let first = results.first { onPick(first) } }
            Rectangle().fill(style.border).frame(height: 0.5)
            if results.isEmpty {
                Text("No matching gitmoji")
                    .font(style.font(13))
                    .foregroundStyle(style.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { row($0) }
                    }
                    .padding(.vertical, GitMetrics.Spacing.xs)
                }
            }
        }
        .frame(width: 320 * style.fontScale, height: 360 * style.fontScale)
        .background(style.surface)
        .onAppear { isSearchFocused = true }
    }

    private func row(_ gitmoji: Gitmoji) -> some View {
        Button { onPick(gitmoji) } label: {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Text(gitmoji.emoji).font(style.font(18)).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(gitmoji.code).font(style.monoCaption).foregroundStyle(style.textPrimary)
                    Text(gitmoji.description).font(style.font(11)).foregroundStyle(style.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, GitMetrics.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(GitmojiRowStyle())
        .help(gitmoji.description)
    }
}

private struct GitmojiRowStyle: ButtonStyle {
    @Environment(\.gitStyle) private var style
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovered || configuration.isPressed ? style.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile, style: .continuous))
            .padding(.horizontal, GitMetrics.Spacing.xs)
            .onHover { isHovered = $0 }
            .gitClickable()
    }
}

#Preview {
    GitmojiPicker { _ in }
}
#endif
