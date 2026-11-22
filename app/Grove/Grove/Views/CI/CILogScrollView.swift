// Views/CI/CILogScrollView.swift
// Grove
//
// Scrolls a CI log, wrapping with the same "Wrap Lines" preference as the diffs.

import SwiftUI

extension EnvironmentValues {
    /// Visible width of a non-wrapping log; `nil` when lines wrap.
    @Entry var logViewportWidth: CGFloat?
    /// Horizontal scroll offset, so line numbers and step headers can stay pinned while lines scroll.
    @Entry var logScrollOffset: CGFloat = 0
}

/// Scrolls a log that fills its panel: both axes without wrapping, vertical only when wrapping.
struct CILogScrollView<Content: View>: View {
    @AppStorage(DiffSettings.wrapLinesKey) private var wrapLines = false
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
                .environment(\.logViewportWidth, geo.size.width)
                .environment(\.logScrollOffset, offset)
            }
        }
    }
}

#Preview {
    CILogScrollView {
        Text("Compiling GroveApp.swift").font(.monoBody).padding()
    }
    .frame(width: 420, height: 200)
    .background(Theme.surface)
}
