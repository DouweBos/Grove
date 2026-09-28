// DesignSystem/ComboBox.swift
// Grove
//
// Native NSComboBox: free-form text with a dropdown of suggestions, which SwiftUI lacks on macOS.

import AppKit
import SwiftUI

struct ComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    var placeholder = ""
    var isMonospaced = false

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.completes = true
        box.numberOfVisibleItems = 12
        box.delegate = context.coordinator
        box.font = isMonospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
        box.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        box.placeholderString = placeholder
        if box.objectValues as? [String] != items {
            box.removeAllItems()
            box.addItems(withObjectValues: items)
        }
        if box.stringValue != text {
            box.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ComboBox

        init(parent: ComboBox) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            parent.text = box.stringValue
        }

        // Fires before `stringValue` updates, so read the picked item directly.
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox, box.indexOfSelectedItem >= 0,
                  let item = box.itemObjectValue(at: box.indexOfSelectedItem) as? String else { return }
            parent.text = item
        }
    }
}

#Preview {
    @Previewable @State var text = "main"
    ComboBox(text: $text, items: ["main", "develop", "feature/auth"], placeholder: "Branch name", isMonospaced: true)
        .frame(width: 240)
        .padding()
}
