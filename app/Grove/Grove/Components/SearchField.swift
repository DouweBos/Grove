// Components/SearchField.swift
// Grove
//
// A macOS-styled search text field with a leading magnifying-glass icon and
// an in-field clear button. Matches the native NSSearchField aesthetic.

import SwiftUI

// MARK: - SearchField

/// A macOS-native-styled search field with a magnifying glass icon on the left,
/// a clear button on the right, and an optional row of filter chips below.
///
/// Usage:
/// ```swift
/// SearchField(text: $query, placeholder: "Filter commits…")
///
/// SearchField(text: $query, placeholder: "Filter files…", tokens: $activeFilters) { token in
///     Text(token)
/// }
/// ```
struct SearchField<TokenLabel: View>: View {

    // MARK: Properties

    @Binding var text: String
    var placeholder: String = "Search"

    // MARK: Token Support

    /// Active filter tokens displayed as chips below the input. Pass `nil` to
    /// omit the token row entirely.
    var tokens: Binding<[String]>?
    /// Builder that renders the label for a single token chip.
    var tokenLabel: ((String) -> TokenLabel)?

    // MARK: State

    @FocusState private var isFocused: Bool

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            inputRow
            if let tokens, !tokens.wrappedValue.isEmpty {
                tokenRow(tokens: tokens)
            }
        }
    }

    // MARK: Input Row

    private var inputRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isFocused
                                ? Color.accentColor.opacity(0.6)
                                : Color.primary.opacity(0.12),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                )
        }
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    // MARK: Token Row

    private func tokenRow(tokens: Binding<[String]>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tokens.wrappedValue, id: \.self) { token in
                    tokenChip(token: token, tokens: tokens)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func tokenChip(token: String, tokens: Binding<[String]>) -> some View {
        HStack(spacing: 4) {
            if let tokenLabel {
                tokenLabel(token)
                    .font(.caption)
                    .foregroundStyle(.primary)
            } else {
                Text(token)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            Button {
                tokens.wrappedValue.removeAll { $0 == token }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

// MARK: - Convenience Init (no tokens)

extension SearchField where TokenLabel == EmptyView {

    /// Creates a search field without token chip support.
    init(text: Binding<String>, placeholder: String = "Search") {
        self._text = text
        self.placeholder = placeholder
        self.tokens = nil
        self.tokenLabel = nil
    }
}

// MARK: - Preview

#Preview("Search Field — Empty") {
    SearchField(text: .constant(""))
        .frame(width: 300)
        .padding()
}

#Preview("Search Field — With Text") {
    SearchField(text: .constant("authentication"), placeholder: "Filter commits…")
        .frame(width: 300)
        .padding()
}

#Preview("Search Field — With Tokens") {
    @Previewable @State var query = ""
    @Previewable @State var tokens = ["Swift", "macOS"]

    SearchField(
        text: $query,
        placeholder: "Filter files…",
        tokens: $tokens
    ) { token in
        Text(token)
    }
    .frame(width: 300)
    .padding()
}
