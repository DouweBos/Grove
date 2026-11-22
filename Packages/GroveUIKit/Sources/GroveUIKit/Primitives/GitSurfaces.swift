// Primitives/GitSurfaces.swift
// GroveUIKit
//
// The cards content sits in: padded, or edge to edge for lists and diffs.

#if os(macOS)
import SwiftUI

private struct GitCardSurface: ViewModifier {
    @Environment(\.gitStyle) private var style
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(style.surface, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: GitMetrics.Radius.card, style: .continuous).strokeBorder(style.border, lineWidth: 0.5))
    }
}

private struct GitPanelSurface: ViewModifier {
    @Environment(\.gitStyle) private var style

    func body(content: Content) -> some View {
        content
            .background(style.surface)
            .clipShape(RoundedRectangle(cornerRadius: GitMetrics.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: GitMetrics.Radius.card, style: .continuous).strokeBorder(style.border, lineWidth: 0.5))
    }
}

extension View {
    /// A card; nil padding is the kit's own.
    public func gitCard(padding: CGFloat? = nil) -> some View {
        modifier(GitCardSurface(padding: padding ?? GitMetrics.Spacing.lg))
    }

    /// A card without padding, for scrolling content that should run to its edges.
    public func gitPanel() -> some View {
        modifier(GitPanelSurface())
    }
}

#Preview {
    Text("Card").gitCard().padding().background(GitUIStyle.system.background)
}
#endif
