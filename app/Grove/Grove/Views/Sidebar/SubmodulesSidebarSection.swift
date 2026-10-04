// Views/Sidebar/SubmodulesSidebarSection.swift
// Grove

import AppKit
import GroveKit
import SwiftUI

/// Submodules with their checkout state. Double-click opens an initialized one in a new tab.
struct SubmodulesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @Environment(WindowViewModel.self) private var windowVM
    @Environment(WindowStore.self) private var windows
    @Environment(\.openWindow) private var openWindow
    @State private var isExpanded = true
    @State private var submoduleToRemove: SubmoduleInfo?

    var body: some View {
        let submodules = viewModel.submodules
        if !submodules.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(submodules) { row($0) }
            } header: {
                SidebarSectionHeader(title: "Submodules", count: submodules.count)
                    .contextMenu {
                        Button("Add Submodule…", systemImage: "plus") { viewModel.requestAddSubmodule() }
                    }
            }
            .confirmationDialog(
                "Remove submodule \u{201C}\(submoduleToRemove?.displayName ?? "")\u{201D}?",
                isPresented: Binding(get: { submoduleToRemove != nil }, set: { if !$0 { submoduleToRemove = nil } }),
                presenting: submoduleToRemove
            ) { submodule in
                Button("Remove Submodule", role: .destructive) { Task { await viewModel.actions.removeSubmodule(submodule) } }
            } message: { submodule in
                Text("Deletes \(submodule.path) and its clone, and stages the removal from .gitmodules. Uncommitted work in it is lost.")
            }
        }
    }

    private func row(_ submodule: SubmoduleInfo) -> some View {
        SidebarRow(title: submodule.displayName, symbol: "shippingbox", tint: tint(submodule.state)) {
            switch submodule.state {
            case .upToDate: EmptyView()
            case .uninitialized: Text("not cloned").font(.system(size: 11, weight: .medium))
            case .modified: Text("modified").font(.system(size: 11, weight: .medium))
            case .conflicted: Text("conflict").font(.system(size: 11, weight: .medium))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openInNewTab(submodule) }
        .help(tooltip(submodule))
        .contextMenu { contextMenu(submodule) }
    }

    @ViewBuilder
    private func contextMenu(_ submodule: SubmoduleInfo) -> some View {
        let isCloned = submodule.state != .uninitialized
        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { openInNewTab(submodule) }
            .disabled(!isCloned)
        Button("Open in This Window", systemImage: "arrow.up.forward.app") {
            windowVM.openReference(RepositoryReference(path: fullURL(submodule).path))
        }
        .disabled(!isCloned)
        Divider()
        if isCloned {
            Button("Update to Recorded Commit", systemImage: "arrow.down.circle") {
                Task { await viewModel.actions.updateSubmodule(submodule, toRemote: false) }
            }
            Button("Update to Latest Remote Commit", systemImage: "arrow.down.to.line.circle") {
                Task { await viewModel.actions.updateSubmodule(submodule, toRemote: true) }
            }
            Button("Fetch", systemImage: "arrow.clockwise") { Task { await viewModel.actions.fetchSubmodule(submodule) } }
        } else {
            Button("Initialize Submodule", systemImage: "arrow.down.circle") { Task { await viewModel.actions.initSubmodule(submodule) } }
        }
        Divider()
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([fullURL(submodule)])
        }
        .disabled(!isCloned)
        Button("Copy Path", systemImage: "doc.on.doc") {
            GroveClipboard.copy(submodule.path)
        }
        Divider()
        Button("Add Submodule…", systemImage: "plus") { viewModel.requestAddSubmodule() }
        Button("Remove Submodule…", systemImage: "trash", role: .destructive) { submoduleToRemove = submodule }
    }

    private func tint(_ state: SubmoduleInfo.State) -> Color {
        switch state {
        case .upToDate: Theme.info
        case .uninitialized: Theme.textSecondary
        case .modified, .conflicted: Theme.warning
        }
    }

    private func tooltip(_ submodule: SubmoduleInfo) -> String {
        var lines = [submodule.path]
        if let url = submodule.url { lines.append(url) }
        if let sha = submodule.shortSHA { lines.append("at \(sha)") }
        if submodule.state == .modified { lines.append("Checked out at a different commit than this repository records.") }
        if submodule.state != .uninitialized { lines.append("Double-click to open in a new tab") }
        return lines.joined(separator: "\n")
    }

    private func fullURL(_ submodule: SubmoduleInfo) -> URL {
        viewModel.repository.path.appendingPathComponent(submodule.path)
    }

    private func openInNewTab(_ submodule: SubmoduleInfo) {
        guard submodule.state != .uninitialized else { return }
        windows.requestTab()
        openWindow(id: GroveApp.mainWindowID, value: RepositoryReference(path: fullURL(submodule).path))
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    let manager = MockRepositoryManager()
    return List {
        SubmodulesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .environment(WindowViewModel(manager: manager))
    .environment(WindowStore(manager: manager))
    .task { await vm.refresh() }
    .frame(width: 240, height: 120)
}
