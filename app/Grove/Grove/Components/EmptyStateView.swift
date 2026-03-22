// Components/EmptyStateView.swift
// Grove
//
// Reusable empty-state placeholder used throughout the app when a list or
// panel has no content to display.

import SwiftUI

// MARK: - EmptyStateView

/// A centred icon + title + optional subtitle + optional action button.
///
/// ```swift
/// EmptyStateView(
///     systemImage: "tray",
///     title: "No Changed Files",
///     subtitle: "Your working tree is clean.",
///     actionTitle: "Refresh"
/// ) {
///     await viewModel.refresh()
/// }
/// ```
struct EmptyStateView: View {

    // MARK: Properties

    let systemImage: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    // MARK: Body

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Empty State") {
    EmptyStateView(
        systemImage: "tray",
        title: "No Changed Files",
        subtitle: "Your working tree is clean.",
        actionTitle: "Refresh"
    ) { }
    .frame(width: 400, height: 300)
}
