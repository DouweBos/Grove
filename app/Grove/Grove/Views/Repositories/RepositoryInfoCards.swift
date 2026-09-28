// Views/Repositories/RepositoryInfoCards.swift
// Grove
//
// Panels shown on the browser's repository summary.

import SwiftUI

/// The latest commits on the checked-out branch.
struct RecentCommitsCard: View {
    let commits: [CommitInfo]
    let branch: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Recent Commits", detail: branch)
            if commits.isEmpty {
                Text("No commits yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.lg)
            } else {
                ForEach(commits) { commit in
                    HStack(spacing: Theme.Spacing.md) {
                        Text(commit.shortSHA)
                            .font(.monoCaption)
                            .foregroundStyle(Theme.accent)
                        Text(commit.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: Theme.Spacing.sm)
                        Text(commit.authorName)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Text(commit.authorDate, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            .font(.monoCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    if commit.id != commits.last?.id {
                        Rectangle().fill(Theme.border).frame(height: 0.5).padding(.leading, Theme.Spacing.lg)
                    }
                }
            }
        }
        .panel()
    }
}

/// Remote names and their URLs.
struct RemotesCard: View {
    let remotes: [RemoteInfo]

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Remotes", detail: "\(remotes.count)")
            ForEach(remotes) { remote in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "cloud")
                        .foregroundStyle(Theme.info)
                        .frame(width: 18)
                    Text(remote.name)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(remote.url)
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .panel()
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        RecentCommitsCard(commits: MockData.commits, branch: "main")
        RemotesCard(remotes: MockData.remotes)
    }
    .padding()
    .frame(width: 640)
    .background(Theme.background)
}
