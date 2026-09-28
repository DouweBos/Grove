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
    @Environment(WindowViewModel.self) private var windowVM
    @State private var worktrees: [WorktreeInfo] = []
    @State private var isExpanded = true
    @State private var worktreeToRemove: WorktreeInfo?

    /// Linked worktrees only (excludes the main worktree).
    private var linkedWorktrees: [WorktreeInfo] {
        worktrees.filter { !$0.isMain }
    }

    var body: some View {
        Group {
            if !linkedWorktrees.isEmpty {
                Section(isExpanded: $isExpanded) {
                    ForEach(linkedWorktrees) { worktreeRow($0) }
                } header: {
                    SidebarSectionHeader(title: "Worktrees", count: linkedWorktrees.count)
                }
            }
        }
        .task(id: viewModel.repository.path) {
            await loadWorktrees()
        }
        .confirmationDialog(
            "Remove this worktree?",
            isPresented: Binding(get: { worktreeToRemove != nil }, set: { if !$0 { worktreeToRemove = nil } }),
            presenting: worktreeToRemove
        ) { worktree in
            Button("Remove Worktree", role: .destructive) {
                Task {
                    await viewModel.removeWorktree(path: worktree.path)
                    await loadWorktrees()
                }
            }
        } message: { worktree in
            Text("The folder \(worktree.displayPath) is deleted. Its branch is kept.")
        }
    }

    // MARK: - Private

    private func worktreeRow(_ worktree: WorktreeInfo) -> some View {
        SidebarRow(title: worktree.branch ?? "Detached HEAD", symbol: "square.on.square", tint: Theme.info) {
            Text(worktree.shortSHA).font(.system(size: 11, design: .monospaced))
        }
        .help(worktree.displayPath)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") {
                windowVM.openReference(RepositoryReference(path: worktree.path))
            }
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
            }
            Divider()
            Button("Remove Worktree…", systemImage: "trash", role: .destructive) {
                worktreeToRemove = worktree
            }
        }
    }

    /// Reads the worktree list by parsing `git worktree list --porcelain` output.
    private func loadWorktrees() async {
        let path = viewModel.repository.path
        // Off the main actor: the git call blocks until it exits.
        let output = await Task.detached { Self.worktreeListOutput(at: path) }.value
        worktrees = output.map(parseWorktreePorcelain) ?? []
    }

    /// Runs `git worktree list --porcelain`.
    nonisolated private static func worktreeListOutput(at repoURL: URL) -> String? {
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
            return nil
        }

        // Read output without blocking the cooperative thread pool.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
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

#Preview {
    List(selection: Binding<SidebarItem?>.constant(nil)) {
        WorktreesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(SidebarViewModel(repository: MockGitRepository()))
    .environment(WindowViewModel(manager: MockRepositoryManager()))
    .frame(width: 240, height: 120)
}
