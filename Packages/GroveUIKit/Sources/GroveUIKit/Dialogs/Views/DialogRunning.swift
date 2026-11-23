// Dialogs/Views/DialogRunning.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

extension DialogOperation {
    /// Runs the form; the app hears of the change either way, and a success closes the dialog.
    func submit(_ title: String, _ form: some GitDialogForm, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        run(title, { progress in try await form.submit(in: context, progress: progress) }) { outcome in
            await context.changed()
            if outcome == true { close(true) }
        }
    }
}

/// Picker of names, off with nothing to pick.
struct NamePicker: View {
    @Environment(\.gitStyle) private var style
    let title: String
    let names: [String]
    @Binding var selection: String
    var isMonospaced = false

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(names, id: \.self) { Text($0).font(isMonospaced ? style.monoCaption : style.font(13)).tag($0) }
        }
        .labelsHidden()
        .disabled(names.isEmpty)
        .gitClickable()
    }
}
#endif
