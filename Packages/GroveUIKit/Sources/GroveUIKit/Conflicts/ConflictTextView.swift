// Conflicts/ConflictTextView.swift
// GroveUIKit
//
// Monospaced plain text in an NSTextView: the merged result's editor, or a read-only side.
// AppKit keeps a 100k-line file responsive where SwiftUI's text views don't.

#if os(macOS)
import AppKit
import Observation
import SwiftUI

/// The merged result as it's being edited. The text stays in the view until it's saved:
/// turning a 300k-line editor's text into a String takes longer than a keystroke may.
@MainActor
@Observable
final class ConflictEditor {
    private(set) var isEdited = false
    private(set) var hasMarkers = false
    @ObservationIgnored fileprivate weak var textView: NSTextView?
    @ObservationIgnored fileprivate var loaded = ""

    /// Shows `text` as the unedited result.
    func load(_ text: String) {
        loaded = text
        textView?.string = text
        isEdited = false
        hasMarkers = text.hasConflictMarkers
    }

    /// The text as edited, converted off the main actor.
    func currentText() async -> String {
        guard isEdited, let storage = textView?.textStorage else { return loaded }
        nonisolated(unsafe) let snapshot = storage.string.copy() as! NSString
        return await Task.detached {
            var text = String(snapshot)
            text.makeContiguousUTF8()
            return text
        }.value
    }

    fileprivate func edited() {
        isEdited = true
        guard let text = textView?.textStorage?.mutableString else { return }
        // Foundation's search on the view's own string, which needs no copy.
        hasMarkers = text.range(of: "<<<<<<< ").location != NSNotFound || text.range(of: ">>>>>>> ").location != NSNotFound
    }
}

struct ConflictTextView: NSViewRepresentable {
    @Environment(\.gitStyle) private var style
    /// Read-only text; ignored when an editor is given.
    var text = ""
    var editor: ConflictEditor?

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
        textView.isEditable = editor != nil
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(editor != nil ? "Merged result" : "Side")
        apply(to: textView, coordinator: context.coordinator)
        if let editor {
            editor.textView = textView
            textView.string = editor.loaded
        } else {
            textView.string = text
            context.coordinator.shown = text
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        guard let textView = scroll.documentView as? NSTextView else { return }
        apply(to: textView, coordinator: context.coordinator)
        // Against the last text shown, not the view's: reading a 100k-line view's string copies it.
        if editor == nil, context.coordinator.shown != text {
            textView.string = text
            context.coordinator.shown = text
        }
    }

    /// The style's font and colour, again only when they changed, so a theme or zoom change shows live.
    private func apply(to textView: NSTextView, coordinator: Coordinator) {
        let look = Coordinator.Look(scale: style.fontScale, text: style.textPrimary, accent: style.accent)
        guard coordinator.look != look else { return }
        coordinator.look = look
        let font = NSFont.monospacedSystemFont(ofSize: 12 * style.fontScale, weight: .regular)
        textView.font = font
        textView.textColor = NSColor(style.textPrimary)
        textView.insertionPointColor = NSColor(style.accent)
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor(style.textPrimary)]
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        struct Look: Equatable {
            let scale: CGFloat
            let text: Color
            let accent: Color
        }

        var editor: ConflictEditor?
        var look: Look?
        var shown = ""

        init(editor: ConflictEditor?) { self.editor = editor }

        func textDidChange(_ notification: Notification) {
            editor?.edited()
        }
    }
}
#endif
