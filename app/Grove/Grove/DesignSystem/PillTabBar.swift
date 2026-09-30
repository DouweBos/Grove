// DesignSystem/PillTabBar.swift
// Grove
//
// Top-level tab switcher: the selected tab is a filled pill.

import SwiftUI

struct PillTab<ID: Hashable>: Identifiable {
    var id: ID
    var title: String
    var symbol: String
    var badge: Int?
    /// A small red dot: something behind this tab needs attention.
    var indicator = false
}

struct PillTabBar<ID: Hashable>: View {
    let tabs: [PillTab<ID>]
    let selection: ID?
    /// Smaller type and padding so the bar fits in a window toolbar.
    var compact = false
    /// Unselected tabs show only their icon, for narrow windows.
    var iconsOnly = false
    let onSelect: (ID) -> Void

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(tabs) { tab in
                let isSelected = tab.id == selection
                Button { onSelect(tab.id) } label: {
                    HStack(spacing: 6) {
                        if iconsOnly && !isSelected {
                            Image(systemName: tab.symbol)
                        } else {
                            Label(tab.title, systemImage: tab.symbol).labelStyle(.titleAndIcon)
                        }
                        if tab.indicator {
                            Circle().fill(Theme.danger).frame(width: 6, height: 6)
                                .accessibilityLabel("Needs attention")
                        }
                        if let badge = tab.badge, badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5)
                                .background(Capsule().fill(isSelected ? Theme.pillSelectedText.opacity(0.2) : Theme.subtleFill))
                        }
                    }
                        .fixedSize()
                        .font(.system(size: compact ? 13 : 14, weight: .medium))
                        .padding(.horizontal, compact ? Theme.Spacing.md : Theme.Spacing.lg)
                        .padding(.vertical, compact ? 5 : Theme.Spacing.sm)
                        .foregroundStyle(isSelected ? Theme.pillSelectedText : Theme.textPrimary)
                        .background {
                            if isSelected {
                                Capsule().fill(Theme.pillSelected).matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

#Preview {
    @Previewable @State var selection = "changes"
    PillTabBar(
        tabs: [
            PillTab(id: "changes", title: "Changes", symbol: "tray", badge: 4),
            PillTab(id: "history", title: "History", symbol: "clock"),
            PillTab(id: "stashes", title: "Stashes", symbol: "tray.2"),
            PillTab(id: "actions", title: "Actions", symbol: "play.circle", indicator: true)
        ],
        selection: selection
    ) { selection = $0 }
    .padding()
    .background(Theme.background)
}
