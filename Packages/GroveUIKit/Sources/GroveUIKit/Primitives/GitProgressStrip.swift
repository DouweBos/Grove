// Primitives/GitProgressStrip.swift
// GroveUIKit
//
// Labeled linear progress with an optional cancel button, for clones, fetches and pushes.

#if os(macOS)
import SwiftUI

public struct GitProgressStrip: View {
    @Environment(\.gitStyle) private var style
    private let title: String
    private let detail: String
    private let fraction: Double?
    private let onCancel: (() -> Void)?

    /// - Parameter fraction: Nil shows an indeterminate bar.
    public init(title: String, detail: String, fraction: Double? = nil, onCancel: (() -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.fraction = fraction
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
            HStack {
                Text(title).font(style.font(13, .medium)).foregroundStyle(style.textPrimary)
                Spacer()
                Text(detail).font(style.monoCaption).foregroundStyle(style.textSecondary)
                if let onCancel {
                    Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .gitClickable()
                        .foregroundStyle(style.textSecondary)
                        .accessibilityLabel("Cancel")
                }
            }
            if let fraction {
                ProgressView(value: fraction).tint(style.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(style.accent)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        GitProgressStrip(title: "Cloning grove", detail: "1,204 of 4,012 objects", fraction: 0.3, onCancel: {})
        GitProgressStrip(title: "Fetching origin", detail: "Resolving deltas")
    }
    .frame(width: 420)
    .padding()
    .background(GitUIStyle.system.surface)
}
#endif
