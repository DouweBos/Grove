// DesignSystem/SwitcherRowStyle.swift
// Grove
//
// A row in a switcher popover: lit while highlighted by hover or arrow keys.

import SwiftUI

struct SwitcherRowStyle: ButtonStyle {
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHighlighted || configuration.isPressed ? Theme.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .padding(.horizontal, Theme.Spacing.xs)
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(["Highlighted", "Plain"], id: \.self) { title in
            Button {} label: {
                Text(title).frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Spacing.sm)
            }
            .buttonStyle(SwitcherRowStyle(isHighlighted: title == "Highlighted"))
        }
    }
    .frame(width: 240)
    .padding(.vertical, Theme.Spacing.xs)
    .background(Theme.surface)
}
