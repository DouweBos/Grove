// Views/Merge/ConflictBannerView.swift
// Grove
//
// Warning banner that replaces the commit composer during a merge or rebase
// conflict state, as a yellow banner.
//
// Design:
//   - Yellow/warning system color for the conflict state
//   - Contextual message: "Rebasing 'X' onto 'Y'" or "Merging 'X' into 'Y'"
//   - "Please resolve all conflicts in order to commit"
//   - Conflict count: "X of Y conflicts remaining"
//   - "Show only conflicts" toggle
//   - "Abort" button that calls abortMerge or abortRebase depending on state

import SwiftUI

// MARK: - ConflictBannerView

/// A warning banner that replaces ``CommitComposerView`` when the repository
/// is in a merge-conflict or rebase-conflict state.
///
/// The banner surfaces all the information and controls needed to guide the
/// user through conflict resolution without leaving the Working Copy view:
///
/// - The current operation type and participating branch names.
/// - A live count of remaining unresolved conflicts.
/// - A toggle to filter the file list to conflicted files only.
/// - An Abort button to safely back out of the operation.
///
/// Usage:
/// ```swift
/// ConflictBannerView(
///     repository: repository,
///     repositoryState: .merge,
///     sourceBranch: "feature/auth",
///     targetBranch: "main",
///     totalConflicts: 5,
///     remainingConflicts: 3,
///     showOnlyConflicts: $showOnlyConflicts
/// )
/// ```
struct ConflictBannerView: View {

    // MARK: Properties

    /// The repository to call abort operations on.
    let repository: any GitRepositoryProtocol

    /// Whether this is a merge or a rebase (determines label text and abort call).
    let repositoryState: RepositoryState

    /// The branch being merged/rebased (left operand — "branch1" in the docs).
    let sourceBranch: String

    /// The branch being merged into / rebased onto (right operand — "branch2").
    let targetBranch: String

    /// Total number of conflicted files detected at the start of conflict resolution.
    let totalConflicts: Int

    /// How many files still have unresolved conflicts.
    let remainingConflicts: Int

    /// Drives the "Show only conflicts" checkbox. Owned by the parent so the
    /// file list can react to changes.
    @Binding var showOnlyConflicts: Bool

    // MARK: Private State

    @State private var isAborting: Bool = false
    @State private var abortError: String?

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main content area
            HStack(alignment: .top, spacing: 10) {
                warningIcon
                messageStack
                Spacer(minLength: 8)
                abortButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider()
                .padding(.top, 10)

            // Footer row: conflict count + show-only checkbox
            HStack(spacing: 12) {
                conflictCountLabel
                Spacer()
                showOnlyConflictsToggle
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(conflictBannerBackground)
        .alert("Abort Failed", isPresented: abortErrorBinding) {
            Button("OK") { abortError = nil }
        } message: {
            if let msg = abortError {
                Text(msg)
            }
        }
    }

    // MARK: Sub-views

    /// Yellow warning triangle matching the screenshot's conflict indicator.
    private var warningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 20))
            .foregroundStyle(.yellow)
            .padding(.top, 1)
    }

    /// Stacked operation description + resolve prompt.
    private var messageStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(operationTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text("Please resolve all conflicts in order to commit.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// "Abort" button — calls the appropriate protocol method.
    private var abortButton: some View {
        Button {
            Task { await performAbort() }
        } label: {
            if isAborting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 40)
            } else {
                Text("Abort")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.red)
        .disabled(isAborting)
    }

    /// "X of Y conflicts remaining" label.
    private var conflictCountLabel: some View {
        let allResolved = remainingConflicts == 0
        return Label {
            Text(conflictCountText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(allResolved ? Color.green : Color.orange)
        } icon: {
            Image(systemName: allResolved ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(allResolved ? Color.green : Color.orange)
        }
    }

    /// "Show only conflicts" checkbox toggle.
    private var showOnlyConflictsToggle: some View {
        Toggle("Show only conflicts", isOn: $showOnlyConflicts)
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    // MARK: Computed Text

    /// Human-readable operation description, e.g. "Rebasing 'main' onto 'develop'".
    private var operationTitle: String {
        switch repositoryState {
        case .rebase, .rebaseInteractive:
            return "Rebasing '\(sourceBranch)' onto '\(targetBranch)'"
        case .merge:
            return "Merging '\(sourceBranch)' into '\(targetBranch)'"
        case .cherrypick:
            return "Cherry-picking onto '\(targetBranch)'"
        case .revert:
            return "Reverting onto '\(targetBranch)'"
        default:
            return "Resolving conflicts on '\(targetBranch)'"
        }
    }

    /// Count string, e.g. "3 of 5 conflicts remaining" or "All conflicts resolved".
    private var conflictCountText: String {
        if remainingConflicts == 0 {
            return "All conflicts resolved"
        } else if remainingConflicts == 1 {
            return "1 of \(totalConflicts) conflict remaining"
        } else {
            return "\(remainingConflicts) of \(totalConflicts) conflicts remaining"
        }
    }

    // MARK: Appearance

    /// Subtle amber-tinted background to differentiate the banner from the
    /// normal commit-composer background without being overpowering.
    private var conflictBannerBackground: some View {
        ZStack {
            Color(white: 0.13)
            Color.yellow.opacity(0.06)
        }
    }

    private var abortErrorBinding: Binding<Bool> {
        Binding(
            get: { abortError != nil },
            set: { if !$0 { abortError = nil } }
        )
    }

    // MARK: Actions

    private func performAbort() async {
        isAborting = true
        defer { isAborting = false }
        do {
            switch repositoryState {
            case .rebase, .rebaseInteractive:
                try await repository.abortRebase()
            default:
                try await repository.abortMerge()
            }
        } catch {
            abortError = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview("Merge Conflict Banner") {
    let repo = MockGitRepository()
    VStack(spacing: 0) {
        ConflictBannerView(
            repository: repo,
            repositoryState: .merge,
            sourceBranch: "feature/auth",
            targetBranch: "main",
            totalConflicts: 5,
            remainingConflicts: 3,
            showOnlyConflicts: .constant(false)
        )
        Divider()
        ConflictBannerView(
            repository: repo,
            repositoryState: .rebase,
            sourceBranch: "main",
            targetBranch: "develop",
            totalConflicts: 2,
            remainingConflicts: 0,
            showOnlyConflicts: .constant(true)
        )
    }
    .frame(width: 320)
    .background(Color(white: 0.13))
}
