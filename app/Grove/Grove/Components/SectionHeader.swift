// Components/SectionHeader.swift
// Grove
//
// Collapsible section header used throughout sidebars and file lists.
// Renders a disclosure triangle, an optional count badge, and an optional
// action button or right-click context menu.

import SwiftUI

// MARK: - SectionHeader

/// A reusable collapsible section header with an optional count badge and
/// a context menu triggered by a `+` button or right-click.
///
/// Usage:
/// ```swift
/// SectionHeader(title: "Branches", isExpanded: $branchesExpanded, count: branches.count)
///
/// SectionHeader(title: "Remotes", isExpanded: $remotesExpanded) {
///     Button("Add Remote…") { addRemote() }
/// }
/// ```
struct SectionHeader<MenuContent: View>: View {

    // MARK: Properties

    let title: String
    @Binding var isExpanded: Bool
    /// Optional count shown in a badge to the right of the title.
    var count: Int? = nil
    /// Content of the context menu (also shown via the `+` button).
    var menuContent: (() -> MenuContent)?

    // MARK: Body

    var body: some View {
        HStack(spacing: 4) {
            // Disclosure triangle + title
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)

                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.3)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            // Count badge
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                    )
            }

            // Action button (visible on hover via contextMenu fallback)
            if let menuContent {
                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contextMenu {
            if let menuContent {
                menuContent()
            }
        }
    }
}

// MARK: - Convenience Init (no menu)

extension SectionHeader where MenuContent == EmptyView {

    /// Creates a section header without a context menu or action button.
    init(title: String, isExpanded: Binding<Bool>, count: Int? = nil) {
        self.title = title
        self._isExpanded = isExpanded
        self.count = count
        self.menuContent = nil
    }
}

// MARK: - Preview

#Preview("Section Headers") {
    @Previewable @State var expanded1 = true
    @Previewable @State var expanded2 = false
    @Previewable @State var expanded3 = true

    VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "Branches", isExpanded: $expanded1, count: 5)

        if expanded1 {
            ForEach(["main", "feature/auth", "fix/crash"], id: \.self) { branch in
                Text(branch)
                    .font(.callout)
                    .padding(.leading, 24)
                    .padding(.vertical, 3)
            }
        }

        Divider()

        SectionHeader(title: "Remotes", isExpanded: $expanded2, count: 2) {
            Button("Add Remote…") { }
        }

        if expanded2 {
            Text("origin")
                .font(.callout)
                .padding(.leading, 24)
                .padding(.vertical, 3)
        }

        Divider()

        SectionHeader(title: "Tags", isExpanded: $expanded3, count: 0)
    }
    .frame(width: 240)
    .padding(.vertical, 8)
}
