// Views/Repositories/RepositoryInfoPanel.swift
// Grove
//
// Shown in the repository browser content area when a bookmark is selected.
// Form-style metadata rows, segmented
// action header, and collapsible Working Copy / Remotes sections.

import SwiftUI

// MARK: - RepositoryInfoPanel

/// Info panel for the selected bookmarked repository.
///
/// Layout:
///  - Header: repo name + icon, "REPOSITORY" label, Open / Delete buttons
///  - Metadata form: Location, Last Opened, Added
///  - WORKING COPY section (branch + status, loaded asynchronously)
///  - REMOTES section (remote name → URL, loaded asynchronously)
struct RepositoryInfoPanel: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel

    let bookmark: RepositoryBookmarkData

    // MARK: State

    @State private var liveInfo: LiveRepoInfo?
    @State private var isLoadingLive = false

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                panelHeader
                Divider()
                metadataSection
                Divider()
                workingCopySection
                Divider()
                remotesSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: bookmark.id) {
            await loadLiveInfo()
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Repo icon + name
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                Text(bookmark.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            // Action row: "REPOSITORY" pill + Open / Delete buttons
            HStack(spacing: 0) {
                Text("REPOSITORY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .selectedContentBackgroundColor).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Spacer()

                Button("Open") {
                    viewModel.openBookmark(bookmark)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Delete", role: .destructive) {
                    viewModel.removeBookmark(bookmark)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoFormRow(label: "Location") {
                HStack(spacing: 6) {
                    Text(bookmark.path)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: bookmark.path)]
                        )
                    } label: {
                        Image(systemName: "arrow.forward.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
            }

            Divider().padding(.leading, 120)

            InfoFormRow(label: "Last Opened") {
                if let lastOpened = bookmark.lastOpenedDate {
                    Text(lastOpened, style: .relative)
                        .font(.callout)
                        .foregroundStyle(.primary)
                } else {
                    Text("Never")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.leading, 120)

            InfoFormRow(label: "Added") {
                Text(bookmark.addedDate, style: .date)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Working Copy Section

    private var workingCopySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoSectionHeader(title: "WORKING COPY")

            if isLoadingLive {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            } else if let info = liveInfo {
                InfoFormRow(label: "Branch") {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(info.currentBranch)
                            .font(.callout)
                    }
                }

                Divider().padding(.leading, 120)

                InfoFormRow(label: "Status") {
                    Text(info.statusSummary)
                        .font(.callout)
                        .foregroundStyle(info.isClean ? .secondary : .primary)
                }
            } else {
                InfoFormRow(label: "Branch") {
                    Text("—")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.leading, 120)

                InfoFormRow(label: "Status") {
                    Text("—")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Remotes Section

    private var remotesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoSectionHeader(title: "REMOTES")

            if let info = liveInfo, !info.remotes.isEmpty {
                ForEach(Array(info.remotes.enumerated()), id: \.offset) { index, remote in
                    if index > 0 {
                        Divider().padding(.leading, 120)
                    }
                    InfoFormRow(label: remote.name) {
                        Text(remote.url)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else if !isLoadingLive {
                InfoFormRow(label: "Remotes") {
                    Text("None configured")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.bottom, 20)
    }

    // MARK: - Live Info Loading

    private func loadLiveInfo() async {
        isLoadingLive = true
        defer { isLoadingLive = false }

        let url = URL(fileURLWithPath: bookmark.path)

        do {
            let repo = try await viewModel.manager.openRepository(at: url)
            async let statusEntries = repo.status()
            async let repoRemotes = repo.remotes()

            let (entries, remoteList) = try await (statusEntries, repoRemotes)

            let changedCount = entries.filter {
                $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified
            }.count

            let statusSummary: String
            let isClean: Bool
            if changedCount == 0 {
                statusSummary = "Clean working tree"
                isClean = true
            } else {
                statusSummary = "\(changedCount) changed \(changedCount == 1 ? "file" : "files")"
                isClean = false
            }

            liveInfo = LiveRepoInfo(
                currentBranch: repo.currentBranch?.name ?? "HEAD detached",
                statusSummary: statusSummary,
                isClean: isClean,
                remotes: remoteList.map { RepoRemote(name: $0.name, url: $0.url) }
            )
        } catch {
            // Not a git repo or cannot open — show dashes for live fields.
            liveInfo = nil
        }
    }
}

// MARK: - Supporting Value Types

/// Snapshot of live repository data for the info panel.
private struct LiveRepoInfo {
    let currentBranch: String
    let statusSummary: String
    let isClean: Bool
    let remotes: [RepoRemote]
}

/// Lightweight remote name + URL pair for display.
private struct RepoRemote {
    let name: String
    let url: String
}

// MARK: - Sub-views

/// A label + value row in the info form.
///
/// The label column is right-aligned at a fixed width so all values
/// start at the same horizontal position.
private struct InfoFormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
                .padding(.trailing, 12)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }
}

/// Uppercase small-caps section header.
private struct InfoSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Preview

#Preview {
    let bookmark = RepositoryBookmarkData(
        id: UUID(),
        path: "/Users/dev/Projects/my-app",
        displayName: "my-app",
        addedDate: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
        lastOpenedDate: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
        sortOrder: 0,
        groupID: nil
    )
    let vm = RepositoryBrowserViewModel(manager: MockRepositoryManager())
    vm.selectedBookmarkID = bookmark.id
    return RepositoryInfoPanel(bookmark: bookmark)
        .environment(vm)
        .frame(width: 580, height: 500)
}
