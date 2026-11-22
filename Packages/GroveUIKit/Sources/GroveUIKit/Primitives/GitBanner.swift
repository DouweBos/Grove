// Primitives/GitBanner.swift
// GroveUIKit
//
// Inline notice with an optional action, e.g. a failed push.

#if os(macOS)
import SwiftUI

public struct GitBanner: View {
    public nonisolated enum Tone: Sendable { case caution, negative, positive }

    @Environment(\.gitStyle) private var style
    private let symbol: String
    private let message: String
    private let tone: Tone
    private let actionTitle: String?
    let action: (() -> Void)?
    let onDismiss: (() -> Void)?

    public init(symbol: String, message: String, tone: Tone = .caution, onDismiss: (() -> Void)? = nil) {
        self.symbol = symbol
        self.message = message
        self.tone = tone
        self.actionTitle = nil
        self.action = nil
        self.onDismiss = onDismiss
    }

    /// `action` is required, so a trailing closure after a title can't be taken for `onDismiss`.
    public init(symbol: String, message: String, tone: Tone = .caution, actionTitle: String,
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
        case .caution: style.warning
        case .negative: style.danger
        case .positive: style.success
        }
    }

    private var fill: Color {
        switch tone {
        case .caution: style.warningFill
        case .negative: style.dangerFill
        case .positive: style.successFill
        }
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.md) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(message)
                .font(style.font(13))
                .foregroundStyle(style.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                // Without a floor, zero-width sizing passes wrap per character and inflate the window.
                .frame(minWidth: 160, alignment: .leading)
            Spacer(minLength: GitMetrics.Spacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action).controlSize(.small).gitClickable()
            }
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .gitClickable()
                    .foregroundStyle(style.textSecondary)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, GitMetrics.Spacing.md)
        .padding(.vertical, GitMetrics.Spacing.sm)
        .background(fill, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.row))
    }
}
#endif
