// DesignSystem/Banner.swift
// Grove
//
// Inline notice with an optional action, e.g. a failed push.

import SwiftUI

struct Banner: View {
    enum Tone { case caution, negative, positive }

    let symbol: String
    let message: String
    let tone: Tone
    let actionTitle: String?
    let action: (() -> Void)?
    let onDismiss: (() -> Void)?

    init(symbol: String, message: String, tone: Tone = .caution, onDismiss: (() -> Void)? = nil) {
        self.symbol = symbol
        self.message = message
        self.tone = tone
        self.actionTitle = nil
        self.action = nil
        self.onDismiss = onDismiss
    }

    /// `action` is required, so a trailing closure after a title can't be taken for `onDismiss`.
    init(symbol: String, message: String, tone: Tone = .caution, actionTitle: String,
         action: @escaping () -> Void, onDismiss: (() -> Void)? = nil) {
        self.symbol = symbol
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    private var color: Color {
        switch tone {
        case .caution: Theme.warning
        case .negative: Theme.danger
        case .positive: Theme.success
        }
    }

    private var fill: Color {
        switch tone {
        case .caution: Theme.bannerFill
        case .negative: Theme.dangerFill
        case .positive: Theme.successFill
        }
    }

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
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
    }
}

#Preview {
    VStack {
        Banner(symbol: "arrow.down.circle", message: "Your branch is 3 commits behind origin/main.",
               actionTitle: "Pull", action: {}, onDismiss: {})
        Banner(symbol: "xmark.octagon", message: "Push rejected: the remote contains work you do not have.", tone: .negative)
        Banner(symbol: "checkmark.circle", message: "Snapshot saved as stash@{0}.", tone: .positive, onDismiss: {})
    }
    .frame(width: 560)
    .padding()
    .background(Theme.background)
}
