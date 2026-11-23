// Dialogs/Template/GitDialogSheet.swift
// GroveUIKit
//
// The layout every dialog shares: header, fields, progress or error, and Cancel beside the primary button.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitDialogSheet<Content: View>: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    private let title: String
    private let message: String?
    private let symbol: String?
    private let width: CGFloat
    private let progress: String?
    private let progressDetail: String
    private let fraction: Double?
    private let errorMessage: String?
    private let primaryTitle: String
    private let cancelTitle: String
    private let isDestructive: Bool
    private let isPrimaryDisabled: Bool
    private let blocker: String?
    private let onCancel: () -> Void
    private let onPrimary: () -> Void
    private let content: () -> Content

    /// Hidden until the message changes or the primary action runs again.
    @State private var dismissedError: String?

    /// - Parameters:
    ///   - progress: Non-nil while the operation runs, as its title.
    ///   - blocker: Why the primary action can't run, shown beside it; the button is off while it's set.
    public init(title: String, message: String? = nil, symbol: String? = nil, width: CGFloat = 460,
                progress: String? = nil, progressDetail: String = "", fraction: Double? = nil, errorMessage: String? = nil,
                primaryTitle: String, cancelTitle: String = "Cancel", isDestructive: Bool = false,
                isPrimaryDisabled: Bool = false, blocker: String? = nil,
                onCancel: @escaping () -> Void, onPrimary: @escaping () -> Void,
                @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.width = width
        self.progress = progress
        self.progressDetail = progressDetail
        self.fraction = fraction
        self.errorMessage = errorMessage
        self.primaryTitle = primaryTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.isPrimaryDisabled = isPrimaryDisabled
        self.blocker = blocker
        self.onCancel = onCancel
        self.onPrimary = onPrimary
        self.content = content
    }

    private var tone: Color { isDestructive ? style.danger : style.accent }
    /// Without cancel, git runs to the end wherever it runs, so the sheet offers no Cancel that wouldn't stop it.
    private var canCancel: Bool { progress == nil || features.contains(.cancel) }

    public var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.lg) {
            header
            content()
            if let progress {
                progressRow(progress).transition(.opacity)
            }
            if let errorMessage, errorMessage != dismissedError {
                GitBanner(symbol: "xmark.octagon", message: errorMessage, tone: .negative,
                          onDismiss: { dismissedError = errorMessage })
                    .transition(.opacity)
            }
            footer
        }
        .padding(GitMetrics.Spacing.xl)
        .frame(width: width * style.fontScale)
        .font(style.font(13))
        .background(style.background)
        .foregroundStyle(style.textPrimary)
        .animation(.easeInOut(duration: 0.15), value: progress)
        .animation(.easeInOut(duration: 0.15), value: errorMessage)
        .animation(.easeInOut(duration: 0.15), value: dismissedError)
        .onChange(of: errorMessage) { dismissedError = nil }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: GitMetrics.Spacing.md) {
            if let symbol {
                Image(systemName: symbol)
                    .font(style.font(17, .medium))
                    .foregroundStyle(tone)
                    .frame(width: 36 * style.fontScale, height: 36 * style.fontScale)
                    .background(tone.opacity(0.14), in: RoundedRectangle(cornerRadius: GitMetrics.Radius.row, style: .continuous))
            }
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
                Text(title).font(style.font(17, .semibold))
                if let message {
                    Text(message)
                        .font(style.font(13))
                        .foregroundStyle(style.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A bar where git reports progress and can be stopped, else a spinner.
    @ViewBuilder
    private func progressRow(_ title: String) -> some View {
        if features.contains(.cancel) {
            GitProgressStrip(title: title, detail: progressDetail, fraction: fraction)
        } else {
            HStack(spacing: GitMetrics.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(title).font(style.font(13, .medium))
                Spacer(minLength: 0)
                Text(progressDetail).font(style.monoCaption).foregroundStyle(style.textSecondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            if let blocker {
                Text(blocker)
                    .font(style.font(12))
                    .foregroundStyle(style.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: GitMetrics.Spacing.sm)
            if canCancel {
                Button(cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .gitClickable()
            }
            Button(primaryTitle, action: submit)
                .buttonStyle(.borderedProminent)
                .tint(tone)
                .keyboardShortcut(.defaultAction)
                .disabled(isPrimaryDisabled || blocker != nil || progress != nil)
                .help(blocker ?? "")
                .gitClickable()
        }
        .controlSize(.large)
    }

    private func submit() {
        guard !isPrimaryDisabled, blocker == nil, progress == nil else { return }
        dismissedError = nil
        onPrimary()
    }
}
#endif
