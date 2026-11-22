// Primitives/GitStatusBadge.swift
// GroveUIKit

#if os(macOS)
import SwiftUI

public struct GitStatusBadge: View {
    public nonisolated enum Tone: Sendable { case positive, caution, negative, neutral }

    @Environment(\.gitStyle) private var style
    private let title: String
    private let symbol: String
    private let tone: Tone

    public init(title: String, symbol: String, tone: Tone) {
        self.title = title
        self.symbol = symbol
        self.tone = tone
    }

    private var color: Color {
        switch tone {
        case .positive: style.success
        case .caution: style.warning
        case .negative: style.danger
        case .neutral: style.textSecondary
        }
    }

    public var body: some View {
        Label(title, systemImage: symbol)
            .font(style.font(11, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, GitMetrics.Spacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

#Preview {
    VStack(alignment: .leading) {
        GitStatusBadge(title: "Merged", symbol: "checkmark.circle.fill", tone: .positive)
        GitStatusBadge(title: "Behind", symbol: "exclamationmark.triangle.fill", tone: .caution)
        GitStatusBadge(title: "Conflicts", symbol: "xmark.octagon.fill", tone: .negative)
        GitStatusBadge(title: "Draft", symbol: "pencil", tone: .neutral)
    }
    .padding()
    .background(GitUIStyle.system.surface)
}
#endif
