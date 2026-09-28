// Views/Sidebar/SubmodulesSidebarSection.swift
// Grove

import SwiftUI

// MARK: - SubmoduleInfo

/// Lightweight description of a git submodule parsed from `.gitmodules`.
struct SubmoduleInfo: Identifiable, Hashable, Sendable {
    /// Submodule name as declared in `.gitmodules` (used as the stable identifier).
    let id: String
    /// Short display name — typically the last path component.
    let name: String
    /// Path relative to the repository root.
    let path: String
    /// Remote URL configured for the submodule.
    let url: String
    /// Currently checked-out SHA inside the submodule working directory, if available.
    let currentSHA: String?

    /// Abbreviated SHA for display (first 7 characters), or `nil` when unknown.
    var shortSHA: String? {
        currentSHA.map { String($0.prefix(7)) }
    }
}

// MARK: - SubmodulesSidebarSection

/// The SUBMODULES section of the sidebar.
///
/// Parses the repository's `.gitmodules` file directly to enumerate submodules.
/// Each row shows the submodule name, its relative path, and the abbreviated SHA
/// of the currently checked-out commit inside that submodule.
struct SubmodulesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @Environment(WindowViewModel.self) private var windowVM
    @State private var submodules: [SubmoduleInfo] = []
    @State private var isExpanded = true

    var body: some View {
        Group {
            if !submodules.isEmpty {
                Section(isExpanded: $isExpanded) {
                    ForEach(submodules) { submoduleRow($0) }
                } header: {
                    SidebarSectionHeader(title: "Submodules", count: submodules.count)
                }
            }
        }
        .task(id: viewModel.repository.path) {
            await loadSubmodules()
        }
    }

    // MARK: - Private

    private func submoduleRow(_ submodule: SubmoduleInfo) -> some View {
        SidebarRow(title: submodule.name, symbol: "shippingbox", tint: Theme.info) {
            if let sha = submodule.shortSHA {
                Text(sha).font(.system(size: 11, design: .monospaced))
            }
        }
        .help("\(submodule.path)\n\(submodule.url)")
        .contextMenu {
            Button("Open Submodule", systemImage: "arrow.up.forward.app") {
                let fullPath = viewModel.repository.path.appendingPathComponent(submodule.path).path
                windowVM.openReference(RepositoryReference(path: fullPath))
            }
            Button("Update Submodule", systemImage: "arrow.down.circle") {
                Task { await viewModel.updateSubmodule(path: submodule.path) }
            }
            Divider()
            Button("Copy Path", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(submodule.path, forType: .string)
            }
        }
    }

    /// Reads and parses the `.gitmodules` file in the repository root.
    ///
    /// The `.gitmodules` format is an INI-like file.  Each submodule block begins
    /// with `[submodule "name"]` and contains `path` and `url` keys.
    private func loadSubmodules() async {
        let gitmodulesURL = viewModel.repository.path
            .appendingPathComponent(".gitmodules")

        guard let contents = try? String(contentsOf: gitmodulesURL, encoding: .utf8) else {
            submodules = []
            return
        }

        submodules = parseGitmodules(contents)
    }

    /// Parses `.gitmodules` INI content into ``SubmoduleInfo`` values.
    private func parseGitmodules(_ contents: String) -> [SubmoduleInfo] {
        var result: [SubmoduleInfo] = []
        var currentName: String?
        var currentPath: String?
        var currentURL: String?

        func flush() {
            guard let name = currentName else { return }
            result.append(SubmoduleInfo(
                id: name,
                name: (currentPath.map { URL(fileURLWithPath: $0).lastPathComponent }) ?? name,
                path: currentPath ?? name,
                url: currentURL ?? "",
                currentSHA: resolveSubmoduleSHA(path: currentPath)
            ))
            currentPath = nil
            currentURL = nil
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[submodule") {
                flush()
                // Extract name from: [submodule "my-lib"]
                let nameRange = trimmed.range(of: "\"([^\"]+)\"", options: .regularExpression)
                currentName = nameRange.map {
                    String(trimmed[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            } else if trimmed.hasPrefix("path") {
                currentPath = keyValue(from: trimmed)
            } else if trimmed.hasPrefix("url") {
                currentURL = keyValue(from: trimmed)
            }
        }
        flush()
        return result
    }

    /// Extracts the value from an `key = value` line.
    private func keyValue(from line: String) -> String? {
        guard let eqIndex = line.firstIndex(of: "=") else { return nil }
        return String(line[line.index(after: eqIndex)...])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Attempts to read the HEAD commit SHA from the submodule's `.git/HEAD`.
    private func resolveSubmoduleSHA(path: String?) -> String? {
        guard let path else { return nil }
        let submoduleRoot = viewModel.repository.path.appendingPathComponent(path)
        let gitDir = submoduleRoot.appendingPathComponent(".git")

        // Try to read the HEAD file — may be a detached SHA or a ref.
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }

        if head.hasPrefix("ref: ") {
            // Resolve the ref to a SHA.
            let refPath = String(head.dropFirst(5))
            let refURL = gitDir.appendingPathComponent(refPath)
            return (try? String(contentsOf: refURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        // Detached HEAD — value is the SHA directly.
        return head.isEmpty ? nil : head
    }
}

// MARK: - Preview

#Preview {
    List(selection: Binding<SidebarItem?>.constant(nil)) {
        SubmodulesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(SidebarViewModel(repository: MockGitRepository()))
    .environment(WindowViewModel(manager: MockRepositoryManager()))
    .frame(width: 240, height: 120)
}
