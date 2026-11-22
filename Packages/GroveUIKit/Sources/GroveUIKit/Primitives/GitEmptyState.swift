// Primitives/GitEmptyState.swift
// GroveUIKit
//
// Centered placeholder for empty lists and panels.

#if os(macOS)
import SwiftUI

public struct GitEmptyState: View {
    @Environment(\.gitStyle) private var style
    private let systemImage: String
    private let title: String
    private let subtitle: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(systemImage: String, title: String, subtitle: String? = nil, actionTitle: String? = nil,
                action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: GitMetrics.Spacing.sm) {
            Image(systemName: systemImage)
                .font(style.font(28, .regular))
                .foregroundStyle(style.textSecondary)
                .frame(width: 56, height: 56)
                .background(style.subtleFill, in: Circle())
                .padding(.bottom, GitMetrics.Spacing.xs)
            Text(title)
                .font(style.font(15, .semibold))
                .foregroundStyle(style.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(style.font(13))
                    .foregroundStyle(style.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .gitClickable()
                    .padding(.top, GitMetrics.Spacing.xs)
            }
        }
        .padding(GitMetrics.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    GitEmptyState(systemImage: "checkmark.seal", title: "Nothing to Commit",
                   subtitle: "Your working tree is clean.", actionTitle: "Refresh") {}
        .frame(width: 400, height: 300)
        .background(GitUIStyle.system.surface)
}
#endif
