// Views/Dialogs/DialogTemplate.swift
// Grove
//
// Shared layout components used across all Grove dialogs.
// Layout: icon + title + description, optional
// Options disclosure group, Cancel + primary button footer.

import SwiftUI

// MARK: - SheetHeader

/// Standard dialog header with title and description text.
///
/// Used at the top of every Grove sheet/dialog.
struct SheetHeader: View {

    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SheetFooter

/// Standard dialog footer with Cancel + primary action buttons.
struct SheetFooter: View {

    let cancelAction: () -> Void
    let primaryLabel: String
    let primaryAction: () -> Void
    var isPrimaryDisabled = false

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", action: cancelAction)
                .keyboardShortcut(.cancelAction)
            Button(primaryLabel, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryDisabled)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

// MARK: - DialogOptionsSection

/// A collapsible "Options" section used in push/pull/fetch dialogs.
struct DialogOptionsSection<Content: View>: View {

    @State private var isExpanded = false
    let content: () -> Content

    init(isExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self._isExpanded = State(initialValue: isExpanded)
        self.content = content
    }

    var body: some View {
        DisclosureGroup("Options", isExpanded: $isExpanded) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

// MARK: - DialogOptionRow

/// A single option row with a checkbox, label, and optional description.
struct DialogOptionRow: View {

    @Binding var isOn: Bool
    let label: String
    let description: String?

    init(isOn: Binding<Bool>, label: String, description: String? = nil) {
        self._isOn = isOn
        self.label = label
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(label, isOn: $isOn)
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Sheet Header + Footer") {
    VStack(spacing: 0) {
        SheetHeader(
            title: "Push HEAD",
            description: "Pushes new commits from your local HEAD branch 'main' to the chosen remote branch."
        )
        Divider()
        DialogOptionsSection(isExpanded: true) {
            DialogOptionRow(isOn: .constant(false), label: "Push All Tags", description: "All refs under refs/tags are pushed.")
            DialogOptionRow(isOn: .constant(false), label: "Force Push", description: "Rewrites remote history. Use with care.")
        }
        Divider()
        SheetFooter(cancelAction: {}, primaryLabel: "Push HEAD", primaryAction: {})
    }
    .frame(width: 440)
}
