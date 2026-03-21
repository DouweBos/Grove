// Views/Blame/BlameFilePicker.swift
// Grove
//
// Entry point for the Blame sidebar item. Shows a file search field
// that lets the user pick a file to blame. Once a file is selected,
// renders the full BlameView.

import SwiftUI

// MARK: - BlameFilePicker

/// Prompts the user to select a file, then displays ``BlameView`` for it.
///
/// Shown when the user navigates to the Blame section in the sidebar.
struct BlameFilePicker: View {

    let repository: any GitRepositoryProtocol

    // MARK: State

    @State private var searchText = ""
    @State private var selectedFile: String?
    @State private var trackedFiles: [String] = []
    @State private var isLoading = false

    // MARK: Body

    var body: some View {
        if let file = selectedFile {
            VStack(spacing: 0) {
                // Back button + file name header
                HStack {
                    Button {
                        selectedFile = nil
                    } label: {
                        Image(systemName: "chevron.left")
                        Text("Back to file picker")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text(file)
                        .font(.subheadline)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                BlameView(filePath: file, repository: repository)
            }
        } else {
            filePickerView
        }
    }

    // MARK: File Picker

    private var filePickerView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search file to blame…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.bar)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading file list…")
                Spacer()
            } else if filteredFiles.isEmpty {
                Spacer()
                EmptyStateView(
                    systemImage: "doc.text.magnifyingglass",
                    title: searchText.isEmpty ? "Blame a File" : "No files found",
                    subtitle: searchText.isEmpty
                        ? "Type a filename above to search, then click to view its blame annotation."
                        : "No files match \"\(searchText)\"."
                )
                Spacer()
            } else {
                List(filteredFiles, id: \.self, selection: $selectedFile) { file in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(file)
                            .font(.subheadline)
                            .fontDesign(.monospaced)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .tag(file)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await loadFiles()
        }
    }

    // MARK: Helpers

    private var filteredFiles: [String] {
        guard !searchText.isEmpty else { return trackedFiles }
        let lower = searchText.lowercased()
        return trackedFiles.filter { $0.lowercased().contains(lower) }
    }

    private func loadFiles() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await repository.status()
            // Use tracked files from status + show all known paths
            // For a complete file list we'd need git ls-files, but status entries work for changed files
            trackedFiles = entries.map(\.path).sorted()

            // If no status entries (clean repo), try to get some files from recent commits
            if trackedFiles.isEmpty {
                let commits = try await repository.log(maxCount: 1, skip: 0, branch: nil)
                if let first = commits.first {
                    let diffs = try await repository.diffForCommit(first.id)
                    trackedFiles = diffs.map(\.path).sorted()
                }
            }
        } catch {
            // Non-critical — user can still type a path
        }
    }
}

// MARK: - Preview

#Preview {
    BlameFilePicker(repository: MockGitRepository())
        .frame(width: 600, height: 400)
}
