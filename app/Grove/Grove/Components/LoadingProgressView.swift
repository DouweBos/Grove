// Components/LoadingProgressView.swift
// Grove
//
// Reusable progress indicator used during background git operations such as
// fetch, push, pull, clone, and checkout.

import SwiftUI

// MARK: - LoadingProgressView

/// A progress indicator supporting indeterminate spinning and determinate
/// progress-bar modes.
///
/// Use the **standard** variant inside content areas and the **compact** variant
/// inside toolbars and status bars.
///
/// ```swift
/// // Indeterminate — e.g. fetching remotes
/// LoadingProgressView(title: "Fetching…")
///
/// // Determinate — e.g. cloning with known byte count
/// LoadingProgressView(title: "Cloning repository…", progress: 0.64)
///
/// // Compact toolbar indicator
/// LoadingProgressView(title: "Pushing…", style: .compact)
/// ```
struct LoadingProgressView: View {

    // MARK: Style

    /// Visual layout variant.
    enum Style {
        /// Full-width card for content areas.
        case standard
        /// Single-line inline layout for toolbars and status bars.
        case compact
    }

    // MARK: Properties

    let title: String
    /// When non-`nil` and in `0.0...1.0`, renders a determinate progress bar.
    /// A `nil` value renders an indeterminate spinner.
    var progress: Double? = nil
    var style: Style = .standard

    // MARK: Body

    var body: some View {
        switch style {
        case .standard:
            standardBody
        case .compact:
            compactBody
        }
    }

    // MARK: Standard Variant

    private var standardBody: some View {
        VStack(spacing: 14) {
            if let progress {
                determinateContent(progress: progress, compact: false)
            } else {
                indeterminateContent(compact: false)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Compact Variant

    private var compactBody: some View {
        HStack(spacing: 8) {
            if let progress {
                determinateContent(progress: progress, compact: true)
            } else {
                indeterminateContent(compact: true)
            }
        }
    }

    // MARK: Content Builders

    @ViewBuilder
    private func indeterminateContent(compact: Bool) -> some View {
        if compact {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func determinateContent(progress: Double, compact: Bool) -> some View {
        let clamped = max(0, min(1, progress))
        let percentage = "\(Int(clamped * 100))%"

        if compact {
            ProgressView(value: clamped)
                .frame(width: 80)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(percentage)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        } else {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                ProgressView(value: clamped)
                    .frame(maxWidth: .infinity)
                Text(percentage)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// MARK: - Preview

#Preview("Standard — Indeterminate") {
    LoadingProgressView(title: "Fetching from origin…")
        .frame(width: 340)
        .padding()
}

#Preview("Standard — Determinate") {
    VStack(spacing: 16) {
        LoadingProgressView(title: "Cloning repository…", progress: 0.0)
        LoadingProgressView(title: "Cloning repository…", progress: 0.37)
        LoadingProgressView(title: "Cloning repository…", progress: 0.74)
        LoadingProgressView(title: "Cloning repository…", progress: 1.0)
    }
    .frame(width: 340)
    .padding()
}

#Preview("Compact Variants") {
    VStack(alignment: .leading, spacing: 12) {
        LoadingProgressView(title: "Pushing…", style: .compact)
        LoadingProgressView(title: "Cloning repository…", progress: 0.55, style: .compact)
    }
    .padding()
}
