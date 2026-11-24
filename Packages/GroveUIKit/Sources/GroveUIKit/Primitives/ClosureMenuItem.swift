// Primitives/ClosureMenuItem.swift
// GroveUIKit
//
// NSMenu only knows target and action; the kit's AppKit menus run closures.

#if os(macOS)
import AppKit

/// A menu item that runs a closure; off with its reason as the tooltip when it can't run.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, problem: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = problem == nil
        toolTip = problem
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
#endif
