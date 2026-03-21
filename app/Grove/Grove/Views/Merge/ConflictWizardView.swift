// Views/Merge/ConflictWizardView.swift
// Grove
//
// The full two-panel conflict-resolution UI.
// Displayed in the right panel (diff area) when a conflicted file is selected.
//
// Layout:
//   Top row: [ConflictVersionPanel (ours)] [ConflictVersionPanel (theirs)]
//   Bottom:  ConflictResolutionArea + "Open in External Merge Tool" button
//
// The view owns the local resolution state (which side is selected) and
// writes that state back to the parent via onResolve when the user confirms.

import SwiftUI

// MARK: - ConflictWizardView

/// Two-panel conflict resolution UI for a single conflicted file.
///
/// Presents the "ours" and "theirs" versions side-by-side, lets the user
/// pick one as the resolution, and surfaces an external-merge-tool escape
/// hatch. The parent is notified via `onResolve` when the user has made
/// a selection.
///
/// ```swift
/// ConflictWizardView(
///     conflictedEntry: entry,
///     oursContent: oursText,
///     theirsContent: theirsText,
///     oursBranch: "feature/auth",
///     theirsBranch: "origin/main",
///     oursAuthor: "Jane Developer",
///     oursDate: Date(),
///     theirsAuthor: "Bob Contributor",
///     theirsDate: someDate,
///     onResolve: { side in … }
/// )
/// ```
struct ConflictWizardView: View {

    // MARK: Properties

    /// The conflicted file entry driving this wizard.
    let conflictedEntry: StatusEntry

    /// Raw text of the "ours" (local HEAD) version. `nil` while loading.
    let oursContent: String?

    /// Raw text of the "theirs" (incoming) version. `nil` while loading.
    let theirsContent: String?

    /// Branch name for the local / HEAD side.
    let oursBranch: String

    /// Branch name for the incoming / remote side.
    let theirsBranch: String

    /// Author of the last commit on the ours side.
    let oursAuthor: String

    /// Date of the last commit on the ours side.
    let oursDate: Date

    /// Author of the last commit on the theirs side.
    let theirsAuthor: String

    /// Date of the last commit on the theirs side.
    let theirsDate: Date

    /// Called when the user selects a version. The parent is responsible for
    /// writing the resolution to the file and marking it as resolved.
    var onResolve: (ConflictSide) -> Void

    /// Called when the user requests the external merge tool.
    ///
    /// When `nil`, the button is wired to ``ExternalToolLauncher`` using the
    /// file URLs below. Provide a custom closure to override that behaviour.
    var onOpenExternalTool: (() -> Void)?

    /// URL of the common-ancestor (base) version on disk. Required for tool launch.
    var baseFileURL: URL?

    /// URL of the local HEAD (ours) version on disk. Required for tool launch.
    var oursFileURL: URL?

    /// URL of the incoming (theirs) version on disk. Required for tool launch.
    var theirsFileURL: URL?

    /// URL of the output (merged result) file on disk. Required for tool launch.
    var mergedFileURL: URL?

    // MARK: Private State

    /// Which side the user has selected as the resolution, if any.
    @State private var selectedSide: ConflictSide?

    // MARK: Computed

    private var resolvedContent: String? {
        guard let side = selectedSide else { return nil }
        return side == .ours ? oursContent : theirsContent
    }

    private var resolvedBranch: String? {
        guard let side = selectedSide else { return nil }
        return side == .ours ? oursBranch : theirsBranch
    }

    private var filename: String {
        URL(fileURLWithPath: conflictedEntry.path).lastPathComponent
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()
            wizardContent
        }
        .background(Color(white: 0.12))
    }

    // MARK: Header

    /// Compact header bar showing the conflicted file path.
    private var wizardHeader: some View {
        HStack(spacing: 8) {
            // Conflict status icon (amber U badge)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0xD2 / 255.0, green: 0x99 / 255.0, blue: 0x22 / 255.0))

            Text(conflictedEntry.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 4)

            Text("Conflict")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Color(red: 0xD2 / 255.0, green: 0x99 / 255.0, blue: 0x22 / 255.0),
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.15))
    }

    // MARK: Main Content

    private var wizardContent: some View {
        VStack(spacing: 12) {
            // Two version panels side-by-side
            versionPanels

            // Resolution area + external tool button
            bottomSection
        }
        .padding(12)
    }

    /// The two version panels arranged horizontally.
    private var versionPanels: some View {
        HStack(spacing: 12) {
            ConflictVersionPanel(
                side: .ours,
                branchName: oursBranch,
                filePath: conflictedEntry.path,
                authorName: oursAuthor,
                authorDate: oursDate,
                content: oursContent,
                isSelected: selectedSide == .ours
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedSide = .ours
                }
                onResolve(.ours)
            }

            ConflictVersionPanel(
                side: .theirs,
                branchName: theirsBranch,
                filePath: conflictedEntry.path,
                authorName: theirsAuthor,
                authorDate: theirsDate,
                content: theirsContent,
                isSelected: selectedSide == .theirs
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedSide = .theirs
                }
                onResolve(.theirs)
            }
        }
        .frame(maxWidth: .infinity)
        // Give the panels a fixed share of the vertical space.
        .frame(minHeight: 180, idealHeight: 220, maxHeight: 320)
    }

    // MARK: Bottom Section

    /// Resolution display area and "Open in External Merge Tool" button.
    private var bottomSection: some View {
        VStack(spacing: 10) {
            ConflictResolutionArea(
                resolvedContent: resolvedContent,
                resolvedSide: selectedSide,
                resolvedBranch: resolvedBranch
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100, idealHeight: 140, maxHeight: 200)

            externalMergeToolButton
        }
    }

    /// "Open in External Merge Tool" button.
    ///
    /// Uses ``ExternalToolLauncher`` when all four file URLs are available;
    /// falls back to `onOpenExternalTool` when provided; otherwise disabled.
    private var externalMergeToolButton: some View {
        let canLaunch = onOpenExternalTool != nil
            || (baseFileURL != nil && oursFileURL != nil
                && theirsFileURL != nil && mergedFileURL != nil)

        return Button {
            launchExternalMergeTool()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                Text("Open in External Merge Tool")
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        // Subtle styling — this is a secondary action after version picking.
        .foregroundStyle(.secondary)
        .disabled(!canLaunch)
    }

    private func launchExternalMergeTool() {
        // If the caller provided a custom closure, prefer it.
        if let onOpenExternalTool {
            onOpenExternalTool()
            return
        }

        // Otherwise launch via ExternalToolLauncher with the provided file URLs.
        guard let base   = baseFileURL,
              let ours   = oursFileURL,
              let theirs = theirsFileURL,
              let merged = mergedFileURL else { return }

        try? ExternalToolLauncher.launchMergeTool(
            base:   base,
            ours:   ours,
            theirs: theirs,
            merged: merged,
            toolPath: AppToolPreferences.mergeToolPath
        )
    }
}

// MARK: - Preview

#Preview("Conflict Wizard — Unresolved") {
    let entry = StatusEntry(
        id: "Sources/App/AuthManager.swift",
        path: "Sources/App/AuthManager.swift",
        indexStatus: .conflicted,
        workdirStatus: .conflicted
    )

    let oursContent = """
    import Foundation

    // AuthManager.swift — feature/auth version
    final class AuthManager {
        private var token: String?

        func authenticate() async throws {
            token = try await OAuthService.shared.fetchToken()
            print("Authenticated via OAuth2")
        }

        func logout() {
            token = nil
        }
    }
    """

    let theirsContent = """
    import Foundation

    // AuthManager.swift — origin/main version
    final class AuthManager {
        private var token: String?

        func authenticate() async throws {
            token = try await LegacyAuthService.shared.fetchToken()
        }

        func logout() {
            token = nil
            NotificationCenter.default.post(name: .authDidLogout, object: nil)
        }
    }
    """

    ConflictWizardView(
        conflictedEntry: entry,
        oursContent: oursContent,
        theirsContent: theirsContent,
        oursBranch: "feature/auth",
        theirsBranch: "origin/main",
        oursAuthor: "Jane Developer",
        oursDate: Calendar.current.date(byAdding: .hour, value: -3, to: Date())!,
        theirsAuthor: "Bob Contributor",
        theirsDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
        onResolve: { _ in },
        onOpenExternalTool: { }
    )
    .frame(width: 720, height: 580)
}

#Preview("Conflict Wizard — Resolved (Ours)") {
    let entry = StatusEntry(
        id: "Sources/App/AuthManager.swift",
        path: "Sources/App/AuthManager.swift",
        indexStatus: .conflicted,
        workdirStatus: .conflicted
    )

    // Pre-set selectedSide by using a wrapper that drives state from outside.
    struct PreviewWrapper: View {
        let entry: StatusEntry
        @State private var side: ConflictSide? = .ours

        var body: some View {
            ConflictWizardView(
                conflictedEntry: entry,
                oursContent: "// Ours content\nfunc authenticate() async throws { … }",
                theirsContent: "// Theirs content\nfunc authenticate() async throws { … }",
                oursBranch: "feature/auth",
                theirsBranch: "origin/main",
                oursAuthor: "Jane Developer",
                oursDate: Date(),
                theirsAuthor: "Bob Contributor",
                theirsDate: Calendar.current.date(byAdding: .hour, value: -5, to: Date())!,
                onResolve: { side = $0 }
            )
        }
    }

    return PreviewWrapper(entry: entry)
        .frame(width: 720, height: 580)
}
