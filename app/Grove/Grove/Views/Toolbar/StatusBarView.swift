// Views/Toolbar/StatusBarView.swift
// Grove
//
// Bottom status bar shown in repository windows.
// Displays background activity (fetch progress, current operation state).

import GroveKit
import SwiftUI

// MARK: - StatusBarView

/// Bottom bar that shows repository activity and status messages.
///
/// Designed to be placed in a `safeAreaInset(edge: .bottom)` modifier.
struct StatusBarView: View {

    // MARK: Dependencies

    let repository: any GitRepositoryProtocol
    /// Optional auto-fetch scheduler. When provided, fetch activity and last-fetch
    /// time are shown in the centre of the bar.
    var autoFetcher: AutoFetchScheduler?

    // MARK: State

    @State private var activityMessage: String?

    // MARK: Body

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            repositoryStateBadge
            Spacer()
            fetchStatusView
            if let branch = repository.currentBranch {
                Label(branch.name, systemImage: "arrow.triangle.branch")
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.monoCaption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: 28)
    }

    // MARK: Fetch Status

    @ViewBuilder
    private var fetchStatusView: some View {
        if let fetcher = autoFetcher {
            if fetcher.isFetching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Fetching\u{2026}")
                }
            } else if let description = fetcher.lastFetchRelativeDescription {
                Text(description)
            }
        } else if let message = activityMessage {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(message)
            }
        }
    }

    // MARK: State Badge

    @ViewBuilder
    private var repositoryStateBadge: some View {
        switch repository.repositoryState {
        case .normal:
            EmptyView()
        case .merge:
            StatusBadge(title: "Merging", symbol: "arrow.triangle.merge", tone: .caution)
        case .rebase, .rebaseInteractive:
            StatusBadge(title: "Rebasing", symbol: "arrow.triangle.pull", tone: .caution)
        case .revert:
            StatusBadge(title: "Reverting", symbol: "arrow.uturn.backward", tone: .caution)
        case .cherrypick:
            StatusBadge(title: "Cherry-picking", symbol: "arrow.right.doc.on.clipboard", tone: .caution)
        case .bisect:
            StatusBadge(title: "Bisecting", symbol: "scope", tone: .caution)
        }
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
