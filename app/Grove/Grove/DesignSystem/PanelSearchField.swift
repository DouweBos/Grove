// DesignSystem/PanelSearchField.swift
// Grove
//
// Rounded filter field that sits at the top of a panel list.

import SwiftUI

struct PanelSearchField: View {
    let placeholder: String
    let text: String
    let onChange: (String) -> Void
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            field
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button { onChange("") } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.tile + 2, style: .continuous))
    }

    @ViewBuilder
    private var field: some View {
        let binding = Binding(get: { text }, set: onChange)
        if let focus {
            TextField(placeholder, text: binding).focused(focus)
        } else {
            TextField(placeholder, text: binding)
        }
    }
}

#Preview {
    VStack {
        PanelSearchField(placeholder: "Filter files", text: "", onChange: { _ in })
        PanelSearchField(placeholder: "Filter files", text: "Theme", onChange: { _ in })
    }
    .padding()
    .frame(width: 300)
    .background(Theme.surface)
}
