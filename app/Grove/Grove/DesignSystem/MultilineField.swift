// DesignSystem/MultilineField.swift
// Grove

import SwiftUI

/// A bordered multi-line text editor with a placeholder, for descriptions and comments.
struct MultilineField: View {
    let text: String
    var placeholder = ""
    var height: CGFloat = 120
    let onChange: (String) -> Void

    var body: some View {
        TextEditor(text: Binding(get: { text }, set: onChange))
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(Theme.Spacing.xs)
            .frame(height: height)
            .background(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm + 1)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

#Preview {
    @Previewable @State var text = ""
    MultilineField(text: text, placeholder: "Leave a comment") { text = $0 }
        .padding()
        .frame(width: 360)
        .background(Theme.surface)
}
