// DesignSystem/StatCard.swift
// Grove
//
// Summary tile: colored label, large rounded number, mono footnote.

import SwiftUI

struct StatCard: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String
    var footnote: String?
    var isSelected = false
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                Text(value)
                    .font(.statValue)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let footnote {
                    Text(footnote)
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(color, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    HStack {
        StatCard(title: "Merged", symbol: "checkmark.circle.fill", color: Theme.success, value: "4",
                 footnote: "safe to delete", isSelected: true) {}
        StatCard(title: "Stale", symbol: "moon.zzz.fill", color: Theme.warning, value: "2", footnote: "no commits in 90d")
        StatCard(title: "Active", symbol: "bolt.fill", color: Theme.info, value: "7", footnote: "recent work")
    }
    .padding()
    .frame(width: 640)
    .background(Theme.background)
}
