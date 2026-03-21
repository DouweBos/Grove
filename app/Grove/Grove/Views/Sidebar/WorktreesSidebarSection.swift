// Views/Sidebar/WorktreesSidebarSection.swift
// Grove

import SwiftUI

// MARK: - WorktreeInfo

/// Describes a single git worktree discovered via `git worktree list --porcelain`.
struct WorktreeInfo: Identifiable, Hashable, Sendable {
    /// Absolute path of the worktree — used as the stable identifier.
    let id: String
    /// Absolute path of the worktree working directory.
    let path: String
    /// Checked-out branch name, or `nil` for a detached HEAD.
    let branch: String?
    /// Current HEAD SHA in this worktree.
    let headSHA: String
    /// `true` for the main worktree (the one that owns the `.git` directory).
    let isMain: Bool

    /// Abbreviated SHA for display (first 7 characters).
    var shortSHA: String { String(headSHA.prefix(7)) }

    /// Display-friendly path using `~` for the home directory prefix.
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - WorktreesSidebarSection

/// The WORKTREES section of the sidebar.
///
/// Lists all linked worktrees (additional checked-out trees created via
/// `git worktree add`). The main worktree is excluded — only linked worktrees
/// are shown. When there are none, a "No additional worktrees" placeholder is
/// displayed.
struct WorktreesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @State private var worktrees: [WorktreeInfo] = []
    @State private var isLoading = false

    /// Linked worktrees only (excludes the main worktree).
    private var linkedWorktrees: [WorktreeInfo] {
        worktrees.filter { !$0.isMain }
    }

    var body: some View {
        Section(header: SidebarSectionHeader(title: "Worktrees")) {
            if isLoading {
                Label {
                    Text("Loading…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if linkedWorktrees.isEmpty {
                Label {
                    Text("No additional worktrees")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } icon: {
                    Image(systemName: "square.on.square.squareshape.controlhandles")
                        .foregroundStyle(.tertiary)
                }
            } else {
                ForEach(linkedWorktrees) { worktree in
                    worktreeRow(worktree)
                }
            }
        }
        .task(id: viewModel.repository.path) {
            await loadWorktrees()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func worktreeRow(_ worktree: WorktreeInfo) -> some View {
        Label {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    if let branch = worktree.branch {
                        Text(branch)
                            .font(.subheadline)
                            .lineLimit(1)
                    } else {
                        Text("Detached HEAD")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(worktree.displayPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                Text(worktree.shortSHA)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: "square.on.square")
                .foregroundStyle(.teal)
        }
        .contextMenu {
            Button("Open in New Window") { }
            Button("Reveal in Finder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: worktree.path))
            }
            Divider()
            Button("Remove Worktree…", role: .destructive) { }
        }
    }

    /// Reads the worktree list by parsing `git worktree list --porcelain` output.
    private func loadWorktrees() async {
        isLoading = true
        defer { isLoading = false }
        worktrees = await parseWorktreeList(at: viewModel.repository.path)
    }

    /// Runs `git worktree list --porcelain` and parses the output.
    private func parseWorktreeList(at repoURL: URL) async -> [WorktreeInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["worktree", "list", "--porcelain"]
        process.currentDirectoryURL = repoURL

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // suppress error output

        do {
            try process.run()
        } catch {
            return []
        }

        // Read output without blocking the cooperative thread pool.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else { return [] }

        return parseWorktreePorcelain(output)
    }

    /// Parses `git worktree list --porcelain` text into ``WorktreeInfo`` values.
    ///
    /// Each entry is separated by a blank line and has the form:
    /// ```
    /// worktree /absolute/path
    /// HEAD <sha>
    /// branch refs/heads/<name>   (or "detached")
    /// ```
    private func parseWorktreePorcelain(_ output: String) -> [WorktreeInfo] {
        var result: [WorktreeInfo] = []
        let blocks = output.components(separatedBy: "\n\n")

        for (index, block) in blocks.enumerated() {
            var path: String?
            var headSHA: String?
            var branch: String?
            var isDetached = false

            for line in block.components(separatedBy: .newlines) {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    headSHA = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    // Convert refs/heads/main -> main
                    if ref.hasPrefix("refs/heads/") {
                        branch = String(ref.dropFirst("refs/heads/".count))
                    } else {
                        branch = ref
                    }
                } else if line == "detached" {
                    isDetached = true
                }
            }

            guard let resolvedPath = path,
                  let resolvedSHA = headSHA
            else { continue }

            result.append(WorktreeInfo(
                id: resolvedPath,
                path: resolvedPath,
                branch: isDetached ? nil : branch,
                headSHA: resolvedSHA,
                isMain: index == 0
            ))
        }

        return result
    }
}

// MARK: - Preview

#Preview("No additional worktrees") {
    let vm = SidebarViewModel(repository: MockGitRepository())

    return List(selection: Binding<SidebarItem?>.constant(nil)) {
        WorktreesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 220, height: 80)
}

#Preview("With worktrees (static)") {
    let vm = SidebarViewModel(repository: MockGitRepository())

    return List(selection: Binding<SidebarItem?>.constant(nil)) {
        Section(header: SidebarSectionHeader(title: "Worktrees")) {
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("feature/auth")
                            .font(.subheadline)
                        Text("~/Projects/my-app-auth")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("a1b2c3d")
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                }
            } icon: {
                Image(systemName: "square.on.square")
                    .foregroundStyle(.teal)
            }
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Detached HEAD")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("~/Projects/my-app-hotfix")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("b2c3d4e")
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                }
            } icon: {
                Image(systemName: "square.on.square")
                    .foregroundStyle(.teal)
            }
        }
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 220, height: 140)
}
