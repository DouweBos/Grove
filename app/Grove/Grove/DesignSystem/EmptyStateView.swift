// DesignSystem/EmptyStateView.swift
// Grove
//
// Centered placeholder for empty lists and panels.

import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, height: 56)
                .background(Theme.subtleFill, in: Circle())
                .padding(.bottom, Theme.Spacing.xs)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(systemImage: "checkmark.seal", title: "Nothing to Commit",
                   subtitle: "Your working tree is clean.", actionTitle: "Refresh") {}
        .frame(width: 400, height: 300)
        .background(Theme.surface)
}
