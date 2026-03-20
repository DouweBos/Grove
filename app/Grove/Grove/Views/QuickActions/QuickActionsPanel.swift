// Views/QuickActions/QuickActionsPanel.swift
// Grove

import SwiftUI

// MARK: - QuickActionsPanel

/// Floating command palette overlay.
///
/// Presents as a centered modal with a dimmed background.  The panel contains:
/// - A search field at the top.
/// - An Items / Filename tab switcher.
/// - A scrollable list of matching results.
///
/// Keyboard handling:
/// - **Up / Down arrows** navigate the result list.
/// - **Return** activates the selected result and dismisses the panel.
/// - **Escape** dismisses without activating.
///
/// `onActivate` is called with the chosen ``SidebarItem`` (if any) so the
/// parent window can update its navigation selection.
struct QuickActionsPanel: View {

    // MARK: - Properties

    @State private var viewModel: QuickActionsViewModel

    /// Called when the user activates a result that maps to a sidebar destination.
    var onActivate: ((SidebarItem) -> Void)?

    // MARK: - Focus State

    @FocusState private var searchFieldFocused: Bool

    // MARK: - Constants

    private static let panelWidth: CGFloat  = 520
    private static let maxListHeight: CGFloat = 360

    // MARK: - Init

    init(
        repository: any GitRepositoryProtocol,
        onActivate: ((SidebarItem) -> Void)? = nil
    ) {
        _viewModel = State(
            initialValue: QuickActionsViewModel(repository: repository)
        )
        self.onActivate = onActivate
    }

    // MARK: - Body

    var body: some View {
        // Dimmed full-screen overlay
        ZStack {
            if viewModel.isPresented {
                // Background dim
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.close()
                    }

                // Floating panel
                panel
                    .frame(width: Self.panelWidth)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.isPresented)
        // Listen for GroveAction.quickActions notifications to toggle the palette.
        .onReceive(
            NotificationCenter.default.publisher(for: GroveAction.notificationName)
        ) { notification in
            guard
                let action = GroveAction(notification: notification),
                action == .quickActions
            else { return }
            if viewModel.isPresented {
                viewModel.close()
            } else {
                viewModel.open()
                searchFieldFocused = true
            }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            Divider()

            // Tab switcher
            tabSwitcher

            Divider()

            // Results list
            resultsList
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))

            TextField("Search\u{2026}", text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($searchFieldFocused)
            .onSubmit {
                activate()
            }
            .onKeyPress(.upArrow) {
                viewModel.selectPrevious()
                return .handled
            }
            .onKeyPress(.downArrow) {
                viewModel.selectNext()
                return .handled
            }
            .onKeyPress(.escape) {
                viewModel.close()
                return .handled
            }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        Picker("Search mode", selection: Binding(
            get: { viewModel.selectedTab },
            set: { viewModel.selectedTab = $0 }
        )) {
            ForEach(QuickActionsTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        if viewModel.results.isEmpty {
            emptyResultsView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            QuickActionRow(
                                result: result,
                                isSelected: index == viewModel.selectedIndex,
                                onMoveToFront: {
                                    moveToFront(resultID: result.id)
                                }
                            )
                            .id(result.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                activate()
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: Self.maxListHeight)
                // Keep the selected row visible when navigating with keyboard.
                .onChange(of: viewModel.selectedIndex) { _, newIndex in
                    if viewModel.results.indices.contains(newIndex) {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(viewModel.results[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 6) {
            Text(viewModel.searchText.isEmpty ? "No items" : "No results")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Actions

    private func activate() {
        if let item = viewModel.activateSelected() {
            onActivate?(item)
        }
    }

    private func moveToFront(resultID: String) {
        // Bubble the matching result to the top of the list.
        // A full implementation would persist this ordering;
        // for now we reorder in-place within the current session.
        guard
            let from = viewModel.results.firstIndex(where: { $0.id == resultID }),
            from > 0
        else { return }
        let item = viewModel.results.remove(at: from)
        viewModel.results.insert(item, at: 0)
        viewModel.selectedIndex = 0
    }
}

// MARK: - QuickActionsToggleModifier

/// View modifier that attaches a ``QuickActionsPanel`` overlay to any view.
///
/// Use this on the root view of a repository window:
/// ```swift
/// RepositoryWindowContent()
///     .quickActions(repository: repository) { item in
///         sidebarSelection = item
///     }
/// ```
struct QuickActionsToggleModifier: ViewModifier {

    let repository: any GitRepositoryProtocol
    var onActivate: ((SidebarItem) -> Void)?

    func body(content: Content) -> some View {
        ZStack {
            content
            QuickActionsPanel(repository: repository, onActivate: onActivate)
        }
    }
}

extension View {
    /// Attaches the Quick Actions command palette to this view.
    func quickActions(
        repository: any GitRepositoryProtocol,
        onActivate: ((SidebarItem) -> Void)? = nil
    ) -> some View {
        modifier(QuickActionsToggleModifier(
            repository: repository,
            onActivate: onActivate
        ))
    }
}

// MARK: - Preview

#Preview {
    let repo = MockGitRepository()

    ZStack {
        // Simulated app background
        Color(NSColor.windowBackgroundColor)
            .frame(width: 900, height: 600)

        QuickActionsPanel(repository: repo, onActivate: { item in
            print("Activated: \(item)")
        })
        .onAppear {
            // Auto-open for preview convenience.
        }
    }
    .frame(width: 900, height: 600)
}
