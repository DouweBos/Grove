// Views/Sidebar/SidebarSectionHeader.swift
// Grove

import SwiftUI

/// Muted section label with an optional count capsule (Branches, Remotes, Tags).
struct SidebarSectionHeader: View {

    let title: String
    var count: Int?

    var body: some View {
        SectionLabel(title: title, count: count)
    }
}

/// Standard 13pt sidebar row: tinted symbol, title, optional mono detail and trailing accessory.
struct SidebarRow<Accessory: View>: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.textSecondary
    var detail: String?
    var isEmphasized = false
    /// Small symbol overlaid on the icon's corner, e.g. a branch that's also checked out in a worktree.
    var badgeSymbol: String?
    var badgeTint: Color = Theme.info
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.backgroundProminence) private var prominence

    /// Fixed tokens are unreadable on the accent selection; hierarchical styles adapt.
    private var isOnSelection: Bool { prominence == .increased }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
                .frame(width: 16)
                .overlay(alignment: .bottomTrailing) {
                    if let badgeSymbol {
                        Image(systemName: badgeSymbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(badgeTint))
                            // A ring in the row background separates the badge from the icon beneath it.
                            .background(Circle().fill(Theme.background).padding(-1.5))
                            .offset(x: 3, y: 3)
                    }
                }
            Text(title)
                .font(.system(size: 13, weight: isEmphasized ? .semibold : .regular))
                .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.textPrimary))
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isOnSelection ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.textSecondary))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            accessory()
                .foregroundStyle(isOnSelection ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.textSecondary))
        }
    }
}

extension SidebarRow where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color = Theme.textSecondary, detail: String? = nil, isEmphasized: Bool = false,
         badgeSymbol: String? = nil) {
        self.init(title: title, symbol: symbol, tint: tint, detail: detail, isEmphasized: isEmphasized,
                  badgeSymbol: badgeSymbol) { EmptyView() }
    }
}

#Preview {
    List {
        Section {
            SidebarRow(title: "main", symbol: "checkmark.circle.fill", tint: Theme.accent, isEmphasized: true)
            SidebarRow(title: "v1.2.0", symbol: "tag", tint: Theme.warning)
            SidebarRow(title: "vendor/lib", symbol: "shippingbox", tint: Theme.info, detail: "a1b2c3d")
        } header: {
            SidebarSectionHeader(title: "Branches", count: 3)
        }
    }
    .listStyle(.sidebar)
    .frame(width: 240, height: 160)
}
