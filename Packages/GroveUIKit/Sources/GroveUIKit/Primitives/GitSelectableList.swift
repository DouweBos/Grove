// Primitives/GitSelectableList.swift
// GroveUIKit
//
// Panel list with rounded selection rows and arrow-key navigation.

#if os(macOS)
import SwiftUI

extension View {
    /// Row chrome for lists inside a panel: rounded selection fill, full-width hit area.
    public func gitSelectableRow(isSelected: Bool) -> some View {
        modifier(SelectableRow(isSelected: isSelected))
    }
}

private struct SelectableRow: ViewModifier {
    @Environment(\.gitStyle) private var style
    let isSelected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: GitMetrics.Radius.row, style: .continuous)
        content
            .padding(.horizontal, GitMetrics.Spacing.sm)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? style.selectionFill : .clear, in: shape)
            .contentShape(shape)
    }
}

public struct GitSelectableList<Item: Identifiable, Row: View>: View {
    private let items: [Item]
    private let selection: Item.ID?
    private let onSelect: (Item) -> Void
    private let row: (Item) -> Row

    public init(items: [Item], selection: Item.ID?, onSelect: @escaping (Item) -> Void,
                @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.selection = selection
        self.onSelect = onSelect
        self.row = row
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            row(item).gitSelectableRow(isSelected: item.id == selection)
                        }
                        .buttonStyle(.plain)
                        .gitClickable()
                        .id(item.id)
                    }
                }
                .padding(GitMetrics.Spacing.sm)
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
    return GitSelectableList(items: rows, selection: 1, onSelect: { _ in }) { row in
        Text(row.title).font(.system(size: 13, weight: .medium))
    }
    .frame(width: 320, height: 300)
    .gitPanel()
    .padding()
}
#endif
