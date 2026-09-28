// Views/WorkingCopy/GitmojiPicker.swift
// Grove
//
// Searchable gitmoji list shown from the commit composer; picking one prefixes the summary.

import SwiftUI

struct GitmojiPicker: View {
    let onPick: (Gitmoji) -> Void

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var results: [Gitmoji] { Gitmoji.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            PanelSearchField(placeholder: "Search gitmoji", text: query, onChange: { query = $0 }, focus: $isSearchFocused)
                .padding(Theme.Spacing.sm)
                .onSubmit { if let first = results.first { onPick(first) } }
            Rectangle().fill(Theme.border).frame(height: 0.5)
            if results.isEmpty {
                Text("No matching gitmoji")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { row($0) }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .frame(width: 320, height: 360)
        .background(Theme.surface)
        .onAppear { isSearchFocused = true }
    }

    private func row(_ gitmoji: Gitmoji) -> some View {
        Button { onPick(gitmoji) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(gitmoji.emoji).font(.system(size: 18)).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(gitmoji.code).font(.monoCaption).foregroundStyle(Theme.textPrimary)
                    Text(gitmoji.description).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(GitmojiRowStyle())
        .help(gitmoji.description)
    }
}

private struct GitmojiRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovered || configuration.isPressed ? Theme.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .padding(.horizontal, Theme.Spacing.xs)
            .onHover { isHovered = $0 }
    }
}

#Preview {
    GitmojiPicker { _ in }
}
