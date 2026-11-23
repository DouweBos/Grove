// History/Sheets/HistorySheetParts.swift
// GroveUIKit
//
// The chrome History's sheets share: icon and title, the error and buttons, the tool sheet's bar.

#if os(macOS)
import GroveKit
import SwiftUI

struct HistorySheetHeader: View {
    @Environment(\.gitStyle) private var style
    let symbol: String
    let title: String
    let message: String
    var isDestructive = false

    var body: some View {
        HStack(alignment: .top, spacing: GitMetrics.Spacing.md) {
            let tint = isDestructive ? style.danger : style.accent
            Image(systemName: symbol)
                .font(style.font(16, .semibold))
                .foregroundStyle(tint)
                .frame(width: 36 * style.fontScale, height: 36 * style.fontScale)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
                Text(title).font(style.font(15, .semibold)).foregroundStyle(style.textPrimary)
                Text(message)
                    .font(style.font(13))
                    .foregroundStyle(style.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The view model's error, then Cancel and the primary action, which shows progress while it runs.
struct HistorySheetFooter: View {
    @Environment(\.gitStyle) private var style
    let viewModel: HistoryViewModel
    let primaryTitle: String
    var isDestructive = false
    var isDisabled = false
    var cancel: (() -> Void)?
    let action: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.sm) {
            if let error = viewModel.errorMessage {
                GitBanner(symbol: "xmark.octagon", message: error, tone: .negative, onDismiss: { viewModel.dismissError() })
            }
            HStack {
                if viewModel.isPerformingAction { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { (cancel ?? viewModel.dismissAction)() }
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle) { Task { await action() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(isDestructive ? style.danger : style.accent)
                    .disabled(isDisabled || viewModel.isPerformingAction)
            }
        }
    }
}

/// Sheet chrome for the larger tools: file history, branch comparison.
struct HistoryToolSheet<Content: View>: View {
    @Environment(\.gitStyle) private var style
    let title: String
    var detail: String?
    let done: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: GitMetrics.Spacing.md) {
            HStack {
                Text(title).font(style.font(15, .semibold)).foregroundStyle(style.textPrimary)
                if let detail {
                    Text(detail).font(style.monoCaption).foregroundStyle(style.textSecondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Done", action: done).keyboardShortcut(.cancelAction)
            }
            content()
        }
        .padding(GitMetrics.Spacing.lg)
        .frame(minWidth: 820, idealWidth: 960, minHeight: 540, idealHeight: 640)
        .background(style.background)
    }
}
#endif
