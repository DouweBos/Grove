// Dialogs/Template/GitComboBox.swift
// GroveUIKit
//
// Native NSComboBox: free-form text with a dropdown of suggestions, which SwiftUI lacks on macOS.

#if os(macOS)
import GroveKit
import AppKit
import SwiftUI

public struct GitComboBox: View {
    @Environment(\.gitStyle) private var style
    @Binding private var text: String
    private let items: [String]
    private let placeholder: String
    private let isMonospaced: Bool

    public init(text: Binding<String>, items: [String], placeholder: String = "", isMonospaced: Bool = false) {
        self._text = text
        self.items = items
        self.placeholder = placeholder
        self.isMonospaced = isMonospaced
    }

    public var body: some View {
        ComboBoxField(text: $text, items: items, placeholder: placeholder,
                      font: isMonospaced ? .monospacedSystemFont(ofSize: 12 * style.fontScale, weight: .regular)
                                         : .systemFont(ofSize: NSFont.systemFontSize * style.fontScale))
    }
}

private struct ComboBoxField: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    let placeholder: String
    let font: NSFont

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.completes = true
        box.numberOfVisibleItems = 12
        box.delegate = context.coordinator
        box.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        box.placeholderString = placeholder
        if box.font != font { box.font = font }
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
        var parent: ComboBoxField

        init(parent: ComboBoxField) { self.parent = parent }

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
    GitComboBox(text: $text, items: ["main", "develop", "feature/auth"], placeholder: "Branch name", isMonospaced: true)
        .frame(width: 240)
        .padding()
}
#endif
