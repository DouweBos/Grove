// Diff/Table/DiffAnnotationView.swift
// GroveUIKit
//
// The app's row under a line: its SwiftUI, inset to line up with the code.

#if os(macOS)
import AppKit
import SwiftUI

final class DiffAnnotationView: NSView, DiffRowContent {
    private var host: NSHostingView<AnyView>?

    override var isFlipped: Bool { true }

    func configure(_ content: AnyView, inset: CGFloat, style: GitUIStyle) {
        let root = AnyView(
            content
                .padding(.leading, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.gitStyle, style))
        if let host {
            host.rootView = root
        } else {
            let host = NSHostingView(rootView: root)
            // The table owns the row's size.
            host.sizingOptions = []
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            addSubview(host)
            self.host = host
        }
    }

    func place(_ geometry: DiffGeometry) {}
}
#endif
