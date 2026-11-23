// Conflicts/ConflictTextView.swift
// GroveUIKit
//
// Monospaced plain text in an NSTextView: the merged result's editor, or a read-only side.
// AppKit keeps a 100k-line file responsive where SwiftUI's text views don't.

#if os(macOS)
import AppKit
import SwiftUI

struct ConflictTextView: NSViewRepresentable {
    @Environment(\.gitStyle) private var style
    @Binding var text: String
    var isEditable = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(isEditable ? "Merged result" : "Side")
        apply(to: textView, coordinator: context.coordinator)
        textView.string = text
        context.coordinator.shown = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        apply(to: textView, coordinator: context.coordinator)
        // Against the last text shown, not the view's: reading a 100k-line view's string copies it.
        if context.coordinator.shown != text {
            textView.string = text
            context.coordinator.shown = text
        }
    }

    /// The style's font and colour, again only when they changed, so a theme or zoom change shows live.
    private func apply(to textView: NSTextView, coordinator: Coordinator) {
        let look = Coordinator.Look(scale: style.fontScale, text: style.textPrimary, accent: style.accent)
        guard coordinator.look != look else { return }
        coordinator.look = look
        textView.isEditable = isEditable
        textView.font = .monospacedSystemFont(ofSize: 12 * style.fontScale, weight: .regular)
        textView.textColor = NSColor(style.textPrimary)
        textView.insertionPointColor = NSColor(style.accent)
        textView.typingAttributes = [.font: textView.font as Any, .foregroundColor: NSColor(style.textPrimary)]
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        struct Look: Equatable {
            let scale: CGFloat
            let text: Color
            let accent: Color
        }

        var text: Binding<String>
        var look: Look?
        var shown = ""

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            shown = textView.string
            text.wrappedValue = shown
        }
    }
}
#endif
