// Views/TabBar/TabBarView.swift
// Grove
//
// Simple tab bar. Only visible when multiple repos are open via Cmd+T.

import SwiftUI

// MARK: - TabBarView

struct TabBarView: View {

    let tabs: [RepositoryReference]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onClose: (Int) -> Void
    let onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.path) { index, ref in
                TabCell(
                    title: ref.displayName,
                    isSelected: selectedIndex == index,
                    onSelect: { onSelect(index) },
                    onClose: { onClose(index) }
                )

                if index < tabs.count - 1
                    && selectedIndex != index
                    && selectedIndex != index + 1 {
                    Divider()
                        .frame(height: 14)
                        .opacity(0.3)
                }
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 28)
        // Slightly darker than the window background by blending a material
        // behind a semi-transparent tint.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            // 1-pt separator that marks the boundary between tabs and content
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 1)
        }
    }
}

// MARK: - TabCell

private struct TabCell: View {

    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Close button — always reserves its space so the title never shifts.
            // The xmark fades in on hover; the circle background appears with it.
            ZStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(Color(nsColor: .quaternaryLabelColor)))
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
            }
            .frame(width: 18)
            .padding(.leading, 6)

            Spacer(minLength: 4)

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            // Balancing spacer keeps the title optically centred
            Color.clear.frame(width: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Selected tab uses windowBackgroundColor so it merges with the content area.
        // Hovered unselected tab shows a lighter tint as a hover affordance.
        .background(
            isSelected
                ? Color(nsColor: .windowBackgroundColor)
                : (isHovering ? Color(nsColor: .windowBackgroundColor).opacity(0.4) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
