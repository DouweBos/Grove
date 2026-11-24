// Shell/GitPillTabBar.swift
// GroveUIKit
//
// The git views' top-level switcher: the selected tab is a filled pill. The app routes; the bar only reports picks.

#if os(macOS)
import SwiftUI

public struct GitPillTab<ID: Hashable>: Identifiable {
    public var id: ID
    public var title: String
    public var symbol: String
    public var badge: Int?
    /// A small dot: something behind this tab needs attention.
    public var indicator: Bool

    public init(id: ID, title: String, symbol: String, badge: Int? = nil, indicator: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.badge = badge
        self.indicator = indicator
    }
}

public struct GitPillTabBar<ID: Hashable>: View {
    @Environment(\.gitStyle) private var style
    private let tabs: [GitPillTab<ID>]
    private let selection: ID?
    private let compact: Bool
    private let iconsOnly: Bool
    private let onSelect: (ID) -> Void

    @Namespace private var namespace

    /// `compact` fits a window toolbar; `iconsOnly` keeps titles off every tab but the selected one.
    public init(tabs: [GitPillTab<ID>], selection: ID?, compact: Bool = false, iconsOnly: Bool = false,
                onSelect: @escaping (ID) -> Void) {
        self.tabs = tabs
        self.selection = selection
        self.compact = compact
        self.iconsOnly = iconsOnly
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            ForEach(tabs) { tab in
                let isSelected = tab.id == selection
                Button { onSelect(tab.id) } label: { label(tab, isSelected: isSelected) }
                    .buttonStyle(.plain)
                    .gitClickable(!isSelected)
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
    }

    private func label(_ tab: GitPillTab<ID>, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            if iconsOnly && !isSelected {
                Image(systemName: tab.symbol)
            } else {
                Label(tab.title, systemImage: tab.symbol).labelStyle(.titleAndIcon)
            }
            if tab.indicator {
                Circle().fill(style.danger).frame(width: 6, height: 6)
                    .accessibilityLabel("Needs attention")
            }
            if let badge = tab.badge, badge > 0 {
                Text("\(badge)")
                    .font(style.font(11, .semibold, .rounded))
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(isSelected ? style.pillSelectedText.opacity(0.2) : style.subtleFill))
            }
        }
        .fixedSize()
        .font(style.font(compact ? 13 : 14, .medium))
        .padding(.horizontal, compact ? GitMetrics.Spacing.md : GitMetrics.Spacing.lg)
        .padding(.vertical, compact ? 5 : GitMetrics.Spacing.sm)
        .foregroundStyle(isSelected ? style.pillSelectedText : style.textPrimary)
        .background {
            if isSelected {
                Capsule().fill(style.pillSelected).matchedGeometryEffect(id: "pill", in: namespace)
            }
        }
        .contentShape(Capsule())
    }
}

#Preview {
    @Previewable @State var selection = "changes"
    GitPillTabBar(
        tabs: [
            GitPillTab(id: "changes", title: "Changes", symbol: "tray", badge: 4),
            GitPillTab(id: "history", title: "History", symbol: "clock"),
            GitPillTab(id: "stashes", title: "Stashes", symbol: "tray.2"),
            GitPillTab(id: "actions", title: "Actions", symbol: "play.circle", indicator: true),
        ],
        selection: selection
    ) { selection = $0 }
    .padding()
    .background(GitUIStyle.system.background)
}
#endif
