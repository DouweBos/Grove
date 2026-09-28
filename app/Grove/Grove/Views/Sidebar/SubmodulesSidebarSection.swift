// Views/Sidebar/SubmodulesSidebarSection.swift
// Grove

import AppKit
import SwiftUI

/// Submodules with their checkout state. Double-click opens an initialized one as a repository.
struct SubmodulesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @Environment(WindowViewModel.self) private var windowVM
    @State private var isExpanded = true

    var body: some View {
        let submodules = viewModel.submodules
        if !submodules.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(submodules) { row($0) }
            } header: {
                SidebarSectionHeader(title: "Submodules", count: submodules.count)
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
        .onTapGesture(count: 2) { open(submodule) }
        .help(tooltip(submodule))
        .contextMenu {
            Button("Open Submodule", systemImage: "arrow.up.forward.app") { open(submodule) }
                .disabled(submodule.state == .uninitialized)
            Button(submodule.state == .uninitialized ? "Initialize Submodule" : "Update Submodule",
                   systemImage: "arrow.down.circle") {
                Task { await viewModel.updateSubmodule(path: submodule.path) }
            }
            Divider()
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([fullURL(submodule)])
            }
            .disabled(submodule.state == .uninitialized)
            Button("Copy Path", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(submodule.path, forType: .string)
            }
        }
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
        if submodule.state != .uninitialized { lines.append("Double-click to open") }
        return lines.joined(separator: "\n")
    }

    private func fullURL(_ submodule: SubmoduleInfo) -> URL {
        viewModel.repository.path.appendingPathComponent(submodule.path)
    }

    private func open(_ submodule: SubmoduleInfo) {
        guard submodule.state != .uninitialized else { return }
        windowVM.openReference(RepositoryReference(path: fullURL(submodule).path))
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    return List {
        SubmodulesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .environment(WindowViewModel(manager: MockRepositoryManager()))
    .task { await vm.refresh() }
    .frame(width: 240, height: 120)
}
