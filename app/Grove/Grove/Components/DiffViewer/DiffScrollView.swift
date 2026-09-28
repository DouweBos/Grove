// Components/DiffViewer/DiffScrollView.swift
// Grove
//
// Scroll containers that give every diff the same line-wrapping behaviour,
// driven by one shared "Wrap Lines" preference.

import SwiftUI

enum DiffPreferences {
    static let wrapLinesKey = "DiffWrapLines"
}

extension EnvironmentValues {
    /// Visible width of a non-wrapping diff; `nil` when lines wrap.
    @Entry var diffViewportWidth: CGFloat?
    /// Horizontal scroll offset, so gutters and hunk headers can stay pinned while lines scroll.
    @Entry var diffScrollOffset: CGFloat = 0
}

/// Scrolls a diff that fills its panel: both axes without wrapping, vertical only when wrapping.
struct DiffScrollView<Content: View>: View {
    @AppStorage(DiffPreferences.wrapLinesKey) private var wrapLines = false
    @State private var offset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if wrapLines {
            ScrollView {
                content().frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    content()
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
                .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.x) } action: { _, x in
                    offset = x
                }
                .environment(\.diffViewportWidth, geo.size.width)
                .environment(\.diffScrollOffset, offset)
            }
        }
    }
}

/// For diffs embedded in an outer vertical scroll view: scrolls sideways unless wrapping.
struct DiffHorizontalScroll<Content: View>: View {
    @AppStorage(DiffPreferences.wrapLinesKey) private var wrapLines = false
    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if wrapLines {
            content()
        } else {
            ScrollView(.horizontal) {
                content()
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { viewportWidth = $0 }
            .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.x) } action: { _, x in
                offset = x
            }
            .environment(\.diffViewportWidth, viewportWidth > 0 ? viewportWidth : nil)
            .environment(\.diffScrollOffset, offset)
        }
    }
}

/// Header button that flips the shared wrap preference for every diff.
struct WrapLinesToggle: View {
    @AppStorage(DiffPreferences.wrapLinesKey) private var wrapLines = false

    var body: some View {
        Button {
            wrapLines.toggle()
        } label: {
            Image(systemName: "arrow.turn.down.left")
                .foregroundStyle(wrapLines ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.borderless)
        .help(wrapLines ? "Don\u{2019}t Wrap Lines" : "Wrap Lines")
        .accessibilityLabel("Wrap Lines")
    }
}

#Preview {
    VStack(spacing: 0) {
        HStack { Spacer(); WrapLinesToggle() }.padding(Theme.Spacing.sm)
        DiffScrollView {
            DiffView(diff: MockData.diffResult(for: "WorkingCopyViewModel.swift"))
        }
    }
    .frame(width: 420, height: 320)
    .panel()
    .padding()
    .background(Theme.background)
}
