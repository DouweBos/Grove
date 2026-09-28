// DesignSystem/Banner.swift
// Grove
//
// Inline notice with an optional action, e.g. a failed push.

import SwiftUI

struct Banner: View {
    enum Tone { case caution, negative }

    let symbol: String
    let message: String
    var tone: Tone = .caution
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var color: Color { tone == .caution ? Theme.warning : Theme.danger }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                // Without a floor, zero-width sizing passes wrap per character and inflate the window.
                .frame(minWidth: 160, alignment: .leading)
            Spacer(minLength: Theme.Spacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action).controlSize(.small)
            }
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(tone == .caution ? Theme.bannerFill : Theme.dangerFill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    }
}

#Preview {
    VStack {
        Banner(symbol: "arrow.down.circle", message: "Your branch is 3 commits behind origin/main.",
               actionTitle: "Pull", action: {}, onDismiss: {})
        Banner(symbol: "xmark.octagon", message: "Push rejected: the remote contains work you do not have.", tone: .negative)
    }
    .frame(width: 560)
    .padding()
    .background(Theme.background)
}
