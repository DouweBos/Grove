// Primitives/GitSearchField.swift
// GroveUIKit
//
// Rounded filter field that sits at the top of a panel list.

#if os(macOS)
import SwiftUI

public struct GitSearchField: View {
    @Environment(\.gitStyle) private var style
    private let placeholder: String
    private let text: String
    private let onChange: (String) -> Void
    private let focus: FocusState<Bool>.Binding?

    public init(placeholder: String, text: String, onChange: @escaping (String) -> Void,
                focus: FocusState<Bool>.Binding? = nil) {
        self.placeholder = placeholder
        self.text = text
        self.onChange = onChange
        self.focus = focus
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(style.font(12, .medium))
                .foregroundStyle(style.textSecondary)
            field
                .textFieldStyle(.plain)
                .font(style.font(13))
            if !text.isEmpty {
                Button { onChange("") } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .gitClickable()
                    .foregroundStyle(style.textSecondary)
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, GitMetrics.Spacing.sm)
        .padding(.vertical, 6)
        .background(style.subtleFill, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile + 2, style: .continuous))
    }

    @ViewBuilder
    private var field: some View {
        let binding = Binding(get: { text }, set: onChange)
        if let focus {
            TextField(placeholder, text: binding).focused(focus)
        } else {
            TextField(placeholder, text: binding)
        }
    }
}

#Preview {
    VStack {
        GitSearchField(placeholder: "Filter files", text: "", onChange: { _ in })
        GitSearchField(placeholder: "Filter files", text: "Theme", onChange: { _ in })
    }
    .padding()
    .frame(width: 300)
    .background(GitUIStyle.system.surface)
}
#endif
