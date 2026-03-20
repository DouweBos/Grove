// Views/Toolbar/StatusBarView.swift
// Grove
//
// Bottom status bar shown in repository windows.
// Displays background activity (fetch progress, current operation state).

import SwiftUI

// MARK: - StatusBarView

/// Bottom bar that shows repository activity and status messages.
///
/// Designed to be placed in a `safeAreaInset(edge: .bottom)` modifier.
struct StatusBarView: View {

    // MARK: Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: State

    @State private var activityMessage: String?
    @State private var progress: Double?

    // MARK: Body

    var body: some View {
        HStack(spacing: 8) {
            // Left: state badge (merge, rebase, etc.)
            repositoryStateBadge

            Spacer()

            // Center: activity message + spinner
            if let message = activityMessage {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Right: current branch
            if let branch = repository.currentBranch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(branch.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: State Badge

    @ViewBuilder
    private var repositoryStateBadge: some View {
        switch repository.repositoryState {
        case .normal:
            EmptyView()
        case .merge:
            StateBadge(label: "MERGING", color: .orange)
        case .rebase, .rebaseInteractive:
            StateBadge(label: "REBASING", color: .blue)
        case .revert:
            StateBadge(label: "REVERTING", color: .purple)
        case .cherrypick:
            StateBadge(label: "CHERRY-PICKING", color: .green)
        case .bisect:
            StateBadge(label: "BISECTING", color: .yellow)
        }
    }
}

// MARK: - StateBadge

private struct StateBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
            )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        Spacer()
        StatusBarView(repository: MockGitRepository())
    }
    .frame(width: 800, height: 50)
}
