// Views/Sidebar/RepositorySwitcher.swift
// Grove
//
// Searchable list of bookmarked repositories shown from the sidebar title, like GitHub's repository dropdown.

import SwiftUI

struct RepositorySwitcher: View {
    @Environment(WindowViewModel.self) private var viewModel

    @State private var query = ""
    @State private var highlightedID: UUID?
    @FocusState private var isSearchFocused: Bool
    /// Resolved once: for a linked worktree it reads the worktree's `.git` file.
    @State private var currentPath: String?

    private var results: [RepositoryBookmarkData] { viewModel.repositorySwitcherItems(matching: query) }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            Text("Switch repository")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], Theme.Spacing.md)
            PanelSearchField(placeholder: "Search repositories", text: query, onChange: setQuery, focus: $isSearchFocused)
                .padding(Theme.Spacing.sm)
                .onSubmit { if let pick = highlighted(in: results) { viewModel.switchRepository(to: pick) } }
                .onKeyPress(.downArrow) { moveHighlight(by: 1, in: results) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1, in: results) }
            Rectangle().fill(Theme.border).frame(height: 0.5)
            list(results)
            Rectangle().fill(Theme.border).frame(height: 0.5)
            Button("Show All Repositories") { viewModel.showAllRepositories() }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.xs)
        }
        .frame(width: 290, height: 380)
        .background(Theme.surface)
        .onAppear {
            currentPath = viewModel.currentBookmarkPath
            isSearchFocused = true
        }
    }

    @ViewBuilder
    private func list(_ results: [RepositoryBookmarkData]) -> some View {
        if results.isEmpty {
            Text("No matching repositories")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { row($0, isHighlighted: $0.id == highlighted(in: results)?.id).id($0.id) }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .onChange(of: highlightedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ bookmark: RepositoryBookmarkData, isHighlighted: Bool) -> some View {
        let isCurrent = bookmark.path == currentPath
        return Button { viewModel.switchRepository(to: bookmark) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .opacity(isCurrent ? 1 : 0)
                    .frame(width: 14)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.displayName)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(abbreviatingHome(bookmark.path))
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SwitcherRowStyle(isHighlighted: isHighlighted))
        .onHover { if $0 { highlightedID = bookmark.id } }
    }

    private func setQuery(_ text: String) {
        query = text
        highlightedID = nil
    }

    /// Defaults to the first result other than the open repository, so Return toggles between the last two.
    private func highlighted(in results: [RepositoryBookmarkData]) -> RepositoryBookmarkData? {
        if let highlightedID, let match = results.first(where: { $0.id == highlightedID }) { return match }
        return results.first { $0.path != currentPath } ?? results.first
    }

    private func moveHighlight(by offset: Int, in results: [RepositoryBookmarkData]) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        let index = highlighted(in: results).flatMap { pick in results.firstIndex { $0.id == pick.id } } ?? 0
        highlightedID = results[min(max(index + offset, 0), results.count - 1)].id
        return .handled
    }
}

private struct SwitcherRowStyle: ButtonStyle {
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHighlighted || configuration.isPressed ? Theme.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .padding(.horizontal, Theme.Spacing.xs)
    }
}

#Preview {
    let vm = WindowViewModel(manager: MockRepositoryManager())
    vm.openReference(RepositoryReference(path: "/Users/dev/Projects/my-app"))
    return RepositorySwitcher()
        .environment(vm)
}
