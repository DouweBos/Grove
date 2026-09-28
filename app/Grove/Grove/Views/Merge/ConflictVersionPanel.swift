// Views/Merge/ConflictVersionPanel.swift
// Grove
//
// One side (ours or theirs) of the two-panel Conflict Wizard.
// Each panel shows:
//   - Header: "Version from 'branch-name'"
//   - File name label + author info chip
//   - Scrollable file content preview (raw text)
//   - "Use This Version" primary action button
//
// The view is intentionally side-agnostic: the caller passes the branch
// name, content, and author metadata for whichever side it represents.

import SwiftUI

// MARK: - ConflictVersionPanel

/// One panel in the two-column ``ConflictWizardView``.
///
/// Displays the branch name, a file metadata chip, a content preview, and
/// a "Use This Version" button. Calls `onSelect` when the user chooses
/// this version as the resolution.
///
/// ```swift
/// ConflictVersionPanel(
///     side: .ours,
///     branchName: "feature/auth",
///     filePath: "Sources/App/AuthManager.swift",
///     authorName: "Jane Developer",
///     authorDate: Date(),
///     content: "// ours content …",
///     isSelected: side == .ours
/// ) {
///     selectedSide = .ours
/// }
/// ```
struct ConflictVersionPanel: View {

    // MARK: Properties

    /// Which side of the conflict this panel represents.
    let side: ConflictSide

    /// Name of the branch this version originates from.
    let branchName: String

    /// Path of the conflicted file, relative to the repository root.
    let filePath: String

    /// Author of the last commit that touched this version.
    let authorName: String

    /// Date of the last commit that touched this version.
    let authorDate: Date

    /// Raw text content for this version of the file.
    /// `nil` indicates the content hasn't loaded yet.
    let content: String?

    /// Whether this side is currently the selected resolution.
    let isSelected: Bool

    /// Called when the user taps "Use This Version".
    var onSelect: () -> Void

    // MARK: Computed

    private var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    private var panelAccentColor: Color {
        isSelected ? .accentColor : Color(white: 0.3)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            fileMetadataChip
            Divider()
            contentPreview
            Divider()
            useThisVersionButton
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
    }

    // MARK: Sub-views

    /// Header bar: "Version from 'branch-name'" with a small side indicator dot.
    private var panelHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sideIndicatorColor)
                .frame(width: 8, height: 8)

            Text("Version from '\(branchName)'")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.18))
    }

    /// File name + author + date chip.
    private var fileMetadataChip: some View {
        HStack(spacing: 8) {
            // File icon
            Image(systemName: "doc.text")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(authorName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(authorDate, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Scrollable monospaced preview of the file content.
    @ViewBuilder
    private var contentPreview: some View {
        if let text = content {
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.10))
        } else {
            // Loading placeholder
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.10))
        }
    }

    /// "Use This Version" button — highlighted when already selected.
    private var useThisVersionButton: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                }
                Text(isSelected ? "Version Selected" : "Use This Version")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            isSelected
                ? Color.accentColor
                : Color.white.opacity(0.07),
            in: Rectangle()
        )
    }

    // MARK: Appearance Helpers

    private var sideIndicatorColor: Color {
        switch side {
        case .ours:   return Color(red: 0x2E / 255.0, green: 0xA0 / 255.0, blue: 0x43 / 255.0)  // green
        case .theirs: return Color(red: 0x58 / 255.0, green: 0xA6 / 255.0, blue: 0xFF / 255.0)  // blue
        }
    }

    private var panelBackground: Color {
        Color(white: 0.14)
    }
}

// MARK: - Preview

#Preview("Conflict Version Panels") {
    let sampleContent = """
    import Foundation

    // AuthManager.swift
    final class AuthManager {
        private var token: String?

        func authenticate() async throws {
            // Feature branch version
            token = try await OAuthService.shared.fetchToken()
        }
    }
    """

    HStack(spacing: 12) {
        ConflictVersionPanel(
            side: .ours,
            branchName: "feature/auth",
            filePath: "Sources/App/AuthManager.swift",
            authorName: "Jane Developer",
            authorDate: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!,
            content: sampleContent,
            isSelected: true
        ) { }

        ConflictVersionPanel(
            side: .theirs,
            branchName: "origin/main",
            filePath: "Sources/App/AuthManager.swift",
            authorName: "Bob Contributor",
            authorDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            content: sampleContent + "\n// main branch extra line\n",
            isSelected: false
        ) { }
    }
    .padding(12)
    .frame(width: 700, height: 380)
    .background(Color(white: 0.11))
}
