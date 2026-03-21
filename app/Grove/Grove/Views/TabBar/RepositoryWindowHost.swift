// Views/TabBar/RepositoryWindowHost.swift
// Grove
//
// Single window host. Shows either the Repositories browser or a repo.
// Opening a repo navigates in-place. Cmd+T adds tabs.

import SwiftUI
import AppKit

// MARK: - BrowserSourceMode

/// Which source is active in the repository browser sidebar.
enum BrowserSourceMode {
    /// Local bookmarks (default). Toggled by the disk icon.
    case local
    /// Connected cloud service repositories. Toggled by the cloud icon.
    case cloud
}

// MARK: - RepositoryWindowHost

struct RepositoryWindowHost: View {

    let manager: any RepositoryManagerProtocol

    // MARK: Navigation State

    /// Current repo shown. nil = browser.
    @State private var openRepo: RepositoryReference?

    // MARK: Tab State (only active after Cmd+T)

    /// Open repo tabs. Empty until user presses Cmd+T.
    @State private var tabs: [RepositoryReference] = []
    @State private var selectedTabIndex: Int = 0

    // MARK: Other State

    @State private var browserVM: RepositoryBrowserViewModel

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
        self._browserVM = State(initialValue: RepositoryBrowserViewModel(manager: manager))
    }

    // MARK: Helpers

    private var isBrowser: Bool { openRepo == nil }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — only when Cmd+T has been used and 2+ repos are open
            if tabs.count > 1 {
                TabBarView(
                    tabs: tabs,
                    selectedIndex: selectedTabIndex,
                    onSelect: { index in
                        selectedTabIndex = clamp(index)
                        openRepo = tabs[selectedTabIndex]
                    },
                    onClose: { index in
                        closeTab(at: index)
                    },
                    onNewTab: {
                        // Go to browser to pick a new repo
                        openRepo = nil
                    }
                )
            }

            // Content
            if let ref = openRepo {
                RepositoryWindowView(reference: ref)
                    .id(ref.path)
            } else {
                RepositoryBrowserView()
                    .environment(browserVM)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { toolbarContent }
        .navigationTitle(openRepo?.displayName ?? "Repositories")
        .onAppear {
            browserVM.onOpenRepo = { [self] (ref: RepositoryReference) in
                openRepo = ref
                // If tabs are active, add this repo to tabs
                if !tabs.isEmpty {
                    if !tabs.contains(where: { $0.path == ref.path }) {
                        tabs.append(ref)
                    }
                    selectedTabIndex = tabs.firstIndex(where: { $0.path == ref.path }) ?? 0
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: GroveTabAction.notificationName)
        ) { notification in
            guard let action = GroveTabAction(notification: notification) else { return }
            handleTabAction(action)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if !isBrowser {
                Button {
                    openRepo = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back to Repositories")
            }
        }
    }

    // MARK: Tab Actions

    private func handleTabAction(_ action: GroveTabAction) {
        switch action {
        case .newTab:
            // Initialize tabs from current state if needed
            if tabs.isEmpty, let current = openRepo {
                tabs = [current]
                selectedTabIndex = 0
            }
            // Navigate to browser to pick a repo
            openRepo = nil

        case .closeTab:
            if tabs.count > 1 {
                closeTab(at: selectedTabIndex)
            } else if !tabs.isEmpty {
                // Last tab — collapse tabs, stay on repo
                tabs.removeAll()
            } else {
                // No tabs — go back to browser
                openRepo = nil
            }

        case .closeWindow:
            NSApplication.shared.keyWindow?.close()

        case .nextTab:
            guard tabs.count > 1 else { return }
            selectedTabIndex = (selectedTabIndex + 1) % tabs.count
            openRepo = tabs[selectedTabIndex]

        case .previousTab:
            guard tabs.count > 1 else { return }
            selectedTabIndex = (selectedTabIndex - 1 + tabs.count) % tabs.count
            openRepo = tabs[selectedTabIndex]
        }
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            openRepo = nil
        } else {
            selectedTabIndex = min(selectedTabIndex, tabs.count - 1)
            openRepo = tabs[selectedTabIndex]
        }
        // Collapse tab bar if only one left
        if tabs.count <= 1 {
            let remaining = tabs.first
            tabs.removeAll()
            openRepo = remaining
        }
    }

    private func clamp(_ index: Int) -> Int {
        guard !tabs.isEmpty else { return 0 }
        return max(0, min(index, tabs.count - 1))
    }
}

#Preview {
    RepositoryWindowHost(manager: MockRepositoryManager())
}
