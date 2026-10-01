// Views/Stack/StackSwitcher.swift
// Grove
//
// Searchable list of the repository's stacks, shown from the Stack tab's title like the repository switcher.

import SwiftUI

struct StackSwitcher: View {
    @Environment(StackViewModel.self) private var viewModel
    let onPick: () -> Void

    @State private var query = ""
    @State private var highlightedID: String?
    @FocusState private var isSearchFocused: Bool

    private var results: [BranchStack] { viewModel.stacks(matching: query) }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            Text("Switch stack")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], Theme.Spacing.md)
            PanelSearchField(placeholder: "Search stacks", text: query, onChange: setQuery, focus: $isSearchFocused)
                .padding(Theme.Spacing.sm)
                .onSubmit { if let pick = highlighted(in: results) { show(pick) } }
                .onKeyPress(.downArrow) { moveHighlight(by: 1, in: results) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1, in: results) }
            Rectangle().fill(Theme.border).frame(height: 0.5)
            list(results)
        }
        .frame(width: 290, height: 300)
        .background(Theme.surface)
        .onAppear { isSearchFocused = true }
    }

    @ViewBuilder
    private func list(_ results: [BranchStack]) -> some View {
        if results.isEmpty {
            Text("No matching stacks")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { row($0, isHighlighted: $0.id == highlighted(in: results)?.id) }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private func row(_ stack: BranchStack, isHighlighted: Bool) -> some View {
        let isCurrent = stack.id == viewModel.stack?.id
        return Button { show(stack) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .opacity(isCurrent ? 1 : 0)
                    .frame(width: 14)
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 12))
                    .foregroundStyle(stack.needsAttention ? Theme.warning : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stack.name)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(stack.layers.count) layer\(stack.layers.count == 1 ? "" : "s") \u{00B7} trunk \(stack.trunk)")
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SwitcherRowStyle(isHighlighted: isHighlighted))
        .onHover { if $0 { highlightedID = stack.id } }
    }

    private func show(_ stack: BranchStack) {
        viewModel.show(stack)
        onPick()
    }

    private func setQuery(_ text: String) {
        query = text
        highlightedID = nil
    }

    /// Defaults to the first stack other than the shown one, so Return toggles between the last two.
    private func highlighted(in results: [BranchStack]) -> BranchStack? {
        if let highlightedID, let match = results.first(where: { $0.id == highlightedID }) { return match }
        return results.first { $0.id != viewModel.stack?.id } ?? results.first
    }

    private func moveHighlight(by offset: Int, in results: [BranchStack]) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        let index = highlighted(in: results).flatMap { pick in results.firstIndex { $0.id == pick.id } } ?? 0
        highlightedID = results[min(max(index + offset, 0), results.count - 1)].id
        return .handled
    }
}

#Preview {
    let refs = RepositoryRefs(repository: MockGitRepository())
    refs.replace(localBranches: MockData.stackBranches, stacks: [MockData.linearStack, MockData.splitStack])
    return StackSwitcher(onPick: {})
        .environment(StackViewModel(repository: MockGitRepository(), refs: refs))
}
