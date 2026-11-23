// Primitives/GitPanelHeader.swift
// GroveUIKit
//
// Title row at the top of a panel: title, optional mono detail, trailing accessories.

#if os(macOS)
import SwiftUI

public struct GitPanelHeader<Accessory: View>: View {
    @Environment(\.gitStyle) private var style
    private let title: String
    private let detail: String?
    private let accessory: () -> Accessory

    public init(title: String, detail: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Text(title)
                .font(style.font(13, .semibold))
                .foregroundStyle(style.textPrimary)
                .lineLimit(1)
                .fixedSize()
            if let detail {
                // In a narrow panel the detail goes rather than show a stub of it.
                ViewThatFits(in: .horizontal) {
                    Text(detail)
                        .font(style.monoCaption)
                        .foregroundStyle(style.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            Spacer(minLength: GitMetrics.Spacing.sm)
            accessory()
        }
        .padding(.horizontal, GitMetrics.Spacing.lg)
        .frame(height: 40 * style.fontScale)
        .overlay(alignment: .bottom) { Rectangle().fill(style.border).frame(height: 0.5) }
    }
}

extension GitPanelHeader where Accessory == EmptyView {
    public init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

#Preview {
    GitPanelHeader(title: "History", detail: "main · 42 commits").frame(width: 420).gitPanel()
}
#endif
