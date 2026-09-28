// DesignSystem/Panel.swift
// Grove
//
// Card that hosts edge-to-edge content (lists, diffs), with an optional header bar.

import SwiftUI

struct PanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

extension View {
    /// A card without padding, for scrolling content that should run to its edges.
    func panel() -> some View {
        modifier(PanelSurface())
    }
}

/// Title row at the top of a panel: title, optional mono detail, trailing accessories.
struct PanelHeader<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            accessory()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }
}

extension PanelHeader where Accessory == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

/// Muted label above a group of rows, e.g. "Branches" or "Staged".
struct SectionLabel<Accessory: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.sectionLabel)
                .foregroundStyle(Theme.textSecondary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.subtleFill, in: Capsule())
            }
            Spacer(minLength: 0)
            accessory()
        }
    }
}

extension SectionLabel where Accessory == EmptyView {
    init(title: String, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

#Preview {
    VStack(spacing: 0) {
        PanelHeader(title: "History", detail: "main · 42 commits") {
            Button { } label: { Image(systemName: "line.3.horizontal.decrease") }.buttonStyle(.borderless)
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Staged", count: 3)
            Text("Sources/App.swift").font(.rowTitle)
        }
        .padding()
        Spacer()
    }
    .frame(width: 420, height: 240)
    .panel()
    .padding()
    .background(Theme.background)
}
