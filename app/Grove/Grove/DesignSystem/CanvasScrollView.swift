// DesignSystem/CanvasScrollView.swift
// Grove
//
// Two-axis scroll view whose content is pinned top-leading and fills the viewport,
// for code and diffs (a plain two-axis ScrollView centers short content).

import SwiftUI

struct CanvasScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                content()
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

#Preview {
    CanvasScrollView {
        Text("let answer = 42\nprint(answer)").font(.monoBody).padding()
    }
    .frame(width: 400, height: 200)
    .panel()
    .padding()
    .background(Theme.background)
}
