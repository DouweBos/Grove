// DesignSystem/CopyButton.swift
// Grove
//
// Icon button that copies a value, highlights on press and briefly shows a checkmark.

import SwiftUI

struct CopyButton: View {
    /// Read when pressed, so a large value isn't built for every render.
    let value: () -> String
    var help = "Copy"
    /// Toast text; defaults to "Copied".
    var confirmation = "Copied"

    init(value: @autoclosure @escaping () -> String, help: String = "Copy", confirmation: String = "Copied") {
        self.value = value
        self.help = help
        self.confirmation = confirmation
    }

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            GroveClipboard.copy(value(), confirmation: confirmation)
            copied = true
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? Theme.success : Theme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IconPressButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Small square hit area with a tinted fill while pressed or hovered.
struct IconPressButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .fill(configuration.isPressed ? Theme.track : hovering ? Theme.subtleFill : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

#Preview {
    HStack {
        Text("8d95099c1a").font(.monoCaption)
        CopyButton(value: "8d95099c1a", help: "Copy SHA", confirmation: "Copied SHA")
    }
    .padding()
    .background(Theme.surface)
}
