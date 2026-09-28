// Views/Dialogs/DialogTemplate.swift
// Grove
//
// Shared sheet layout for every Grove dialog: header, fields card,
// progress / error status, and a Cancel + primary footer.

import SwiftUI

// MARK: - DialogSheet

struct DialogSheet<Content: View>: View {

    let title: String
    var message: String?
    var symbol: String?
    var width: CGFloat = 460
    /// Non-nil while the operation runs; shown as a ProgressStrip title.
    var progress: String?
    var progressDetail = ""
    var fraction: Double?
    var errorMessage: String?
    let primaryTitle: String
    var isDestructive = false
    var isPrimaryDisabled = false
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            content()
            if let progress {
                ProgressStrip(title: progress, detail: progressDetail, fraction: fraction)
                    .transition(.opacity)
            }
            if let errorMessage {
                Banner(symbol: "xmark.octagon", message: errorMessage, tone: .negative)
                    .transition(.opacity)
            }
            footer
        }
        .padding(Theme.Spacing.xl)
        .frame(width: width)
        .background(Theme.background)
        .foregroundStyle(Theme.textPrimary)
        .animation(.easeInOut(duration: 0.15), value: progress)
        .animation(.easeInOut(duration: 0.15), value: errorMessage)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isDestructive ? Theme.danger : Theme.accent)
                    .frame(width: 36, height: 36)
                    .background((isDestructive ? Theme.danger : Theme.accent).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if let message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.borderedProminent)
                .tint(isDestructive ? Theme.danger : Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(isPrimaryDisabled || progress != nil)
        }
        .controlSize(.large)
    }
}

// MARK: - DialogCard

/// Rounded card grouping a dialog's fields.
struct DialogCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.md)
    }
}

// MARK: - DialogField

/// Label + control row with a fixed label column so controls line up.
struct DialogField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 96, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Mono path display with a Choose… button, for folder pickers.
struct DialogPathField: View {
    let path: String?
    var placeholder = "No folder selected"
    let onChoose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(path.map(abbreviatingHome) ?? placeholder)
                .font(.monoCaption)
                .foregroundStyle(path == nil ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose…", action: onChoose)
        }
    }
}

/// `~/Projects/x` instead of `/Users/me/Projects/x`.
func abbreviatingHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

/// Stashes uncommitted changes, returning whether a stash was created, so callers
/// never pop an unrelated older stash afterwards.
func stashIfDirty(_ repository: any GitRepositoryProtocol, message: String) async throws -> Bool {
    let isDirty = try await repository.status().contains {
        $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified
    }
    if isDirty {
        try await repository.stashCreate(message: message, includeUntracked: true, paths: nil)
    }
    return isDirty
}

// MARK: - DialogOptionsSection

/// Collapsible "Options" card used in push/pull/fetch dialogs.
struct DialogOptionsSection<Content: View>: View {

    @State private var isExpanded: Bool
    let content: () -> Content

    init(isExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self._isExpanded = State(initialValue: isExpanded)
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                content()
            }
            .padding(.top, Theme.Spacing.sm)
        } label: {
            Text("Options")
                .font(.sectionLabel)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.md)
    }
}

// MARK: - DialogOptionRow

/// Checkbox with an optional one-line explanation underneath.
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
                .font(.system(size: 13))
            if let description {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preview

#Preview("Dialog") {
    DialogSheet(
        title: "Push main",
        message: "Sends your local commits on 'main' to the chosen remote branch.",
        symbol: "arrow.up.to.line",
        progress: "Pushing to origin…",
        errorMessage: "Push rejected: the remote contains work you do not have.",
        primaryTitle: "Push",
        onCancel: {},
        onPrimary: {}
    ) {
        DialogCard {
            DialogField("Destination") { Text("origin/main").font(.monoCaption) }
            DialogField("Location") { DialogPathField(path: "/Users/me/Projects/grove") {} }
        }
        DialogOptionsSection(isExpanded: true) {
            DialogOptionRow(isOn: .constant(false), label: "Push All Tags", description: "All refs under refs/tags are pushed.")
            DialogOptionRow(isOn: .constant(true), label: "Force Push", description: "Rewrites remote history. Use with care.")
        }
    }
}
