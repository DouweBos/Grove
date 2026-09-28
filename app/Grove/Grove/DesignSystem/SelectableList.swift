// DesignSystem/SelectableList.swift
// Grove
//
// Panel list with rounded selection rows and arrow-key navigation.

import SwiftUI

extension View {
    /// Row chrome for lists inside a panel: rounded selection fill, full-width hit area.
    func selectableRow(isSelected: Bool) -> some View {
        padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}

struct SelectableList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let selection: Item.ID?
    let onSelect: (Item) -> Void
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            row(item).selectableRow(isSelected: item.id == selection)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(by: 1) }
            .onKeyPress(.upArrow) { move(by: -1) }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
            }
        }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let current = items.firstIndex { $0.id == selection }
        let next = current.map { min(max($0 + offset, 0), items.count - 1) } ?? 0
        onSelect(items[next])
        return .handled
    }
}

#Preview {
    struct Row: Identifiable { let id: Int; let title: String }
    let rows = (0..<6).map { Row(id: $0, title: "stash@{\($0)}: WIP on main") }
    return SelectableList(items: rows, selection: 1, onSelect: { _ in }) { row in
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title).font(.rowTitle)
            Text("a1b2c3d · 2 hours ago").font(.monoCaption).foregroundStyle(Theme.textSecondary)
        }
    }
    .frame(width: 320, height: 300)
    .panel()
    .padding()
    .background(Theme.background)
}
