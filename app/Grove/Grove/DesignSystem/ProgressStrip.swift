// DesignSystem/ProgressStrip.swift
// Grove
//
// Labeled linear progress with an optional cancel button, for clones, fetches and pushes.

import SwiftUI

struct ProgressStrip: View {
    let title: String
    let detail: String
    /// Nil shows an indeterminate bar.
    var fraction: Double?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(detail).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                if let onCancel {
                    Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Cancel")
                }
            }
            if let fraction {
                ProgressView(value: fraction).tint(Theme.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Theme.accent)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressStrip(title: "Cloning grove", detail: "1,204 of 4,012 objects", fraction: 0.3, onCancel: {})
        ProgressStrip(title: "Fetching origin", detail: "Resolving deltas")
    }
    .frame(width: 420)
    .padding()
    .background(Theme.surface)
}
