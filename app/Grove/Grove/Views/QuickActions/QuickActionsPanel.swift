// Views/QuickActions/QuickActionsPanel.swift
// Grove
//
// Floating command palette (Cmd+Shift+A): commands, views, refs, commits and files.

import GroveKit
import SwiftUI

struct QuickActionsPanel: View {

    @State private var viewModel: QuickActionsViewModel
    @FocusState private var isSearchFocused: Bool
    // Menu commands reach every window; only the key one answers.
    @Environment(\.appearsActive) private var appearsActive

    private static let width: CGFloat = 600
    private static let listHeight: CGFloat = 380

    init(session: RepositorySession) {
        _viewModel = State(initialValue: QuickActionsViewModel(session: session))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.close() }
                panel
                    .frame(width: Self.width)
                    .padding(.top, 60)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.18), value: viewModel.isPresented)
        .onReceive(NotificationCenter.default.publisher(for: GroveAction.notificationName)) { note in
            guard appearsActive else { return }
            switch GroveAction(notification: note) {
            case .quickActions: viewModel.toggle()
            case .quickOpen: viewModel.openFiles()
            default: return
            }
            isSearchFocused = viewModel.isPresented
        }
        .alert("Couldn't Open", isPresented: Binding(get: { viewModel.errorMessage != nil },
                                                    set: { if !$0 { viewModel.dismissError() } })) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            searchRow
            PillTabBar(tabs: QuickActionsTab.allCases.map { PillTab(id: $0, title: $0.rawValue, symbol: $0 == .items ? "command" : "doc.text") },
                       selection: viewModel.selectedTab, compact: true) { viewModel.selectTab($0) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            Rectangle().fill(Theme.border).frame(height: 0.5)
            results
            footer
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        .shadow(radius: 28, y: 12)
    }

    private var searchRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            TextField(viewModel.selectedTab == .items ? "Run a command, jump to a branch or commit\u{2026}" : "Find a file to blame\u{2026}",
                      text: Binding(get: { viewModel.searchText }, set: viewModel.setSearchText))
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .focused($isSearchFocused)
                .onSubmit { viewModel.activateSelected() }
                .onKeyPress(.upArrow) { viewModel.moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow) { viewModel.moveSelection(by: 1); return .handled }
                .onKeyPress(.escape) { viewModel.close(); return .handled }
                .onKeyPress(.tab) {
                    viewModel.selectTab(viewModel.selectedTab == .items ? .files : .items)
                    return .handled
                }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    viewModel.activateSelected(alternate: true)
                    return .handled
                }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.results.isEmpty {
            Text(viewModel.searchText.isEmpty ? "Loading\u{2026}" : "No matches for \u{201C}\(viewModel.searchText)\u{201D}")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            QuickActionRow(result: result)
                                .selectableRow(isSelected: index == viewModel.selectedIndex)
                                .id(result.id)
                                .onTapGesture {
                                    viewModel.highlight(index)
                                    viewModel.activateSelected()
                                }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
                .frame(maxHeight: Self.listHeight)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: viewModel.selectedIndex) { _, index in
                    guard viewModel.results.indices.contains(index) else { return }
                    proxy.scrollTo(viewModel.results[index].id)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.lg) {
            hint("\u{2191}\u{2193}", "navigate")
            hint("\u{21A9}", viewModel.selectedTab == .files ? "blame" : "run")
            if viewModel.selectedTab == .files { hint("\u{2318}\u{21A9}", "open in editor") }
            hint("\u{21E5}", "switch tab")
            Spacer()
            hint("esc", "close")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(key).font(.monoCaption).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Row

private struct QuickActionRow: View {
    let result: QuickActionResult

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: result.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(result.kind)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Mounting

extension View {
    /// Overlays the Quick Actions palette; it opens on `GroveAction.quickActions`.
    func quickActions(session: RepositorySession) -> some View {
        overlay { QuickActionsPanel(session: session) }
    }
}

#Preview {
    let session = RepositorySession(repository: MockGitRepository())
    return Theme.background
        .frame(width: 900, height: 600)
        .quickActions(session: session)
        .onAppear { GroveAction.quickActions.post() }
}
