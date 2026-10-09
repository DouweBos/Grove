// Views/Sidebar/TagsSidebarSection.swift
// Grove

import GroveKit
import SwiftUI

/// Tags, collapsed by default since repositories often have many. Hidden when there are none.
struct TagsSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    @State private var isExpanded = false

    var body: some View {
        if !viewModel.tags.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(viewModel.tags) { tagRow($0) }
            } header: {
                SidebarSectionHeader(title: "Tags", count: viewModel.tags.count)
            }
        }
    }

    private func tagRow(_ tag: TagInfo) -> some View {
        SidebarRow(title: tag.name, symbol: tag.isAnnotated ? "tag.fill" : "tag", tint: Theme.warning)
            .tag(SidebarItem.tag(tag))
            .draggable(tag.name)
            .contextMenu {
                Button("New Branch from \u{201C}\(tag.name)\u{201D}…", systemImage: "arrow.triangle.branch") {
                    viewModel.present(.createBranch(from: tag.name))
                }
                Button("Copy Name", systemImage: "doc.on.doc") {
                    GroveClipboard.copy(tag.name)
                }
                Button("Reveal in History", systemImage: "clock.arrow.circlepath") { viewModel.revealInHistory(.tag(tag)) }
                ExportFilesButton(ref: tag.name)
                Divider()
                Button("Delete Tag…", systemImage: "trash", role: .destructive) {
                    viewModel.requestConfirmation(.deleteTag(tag))
                }
            }
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.refs.replace(tags: MockData.tags)
    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        TagsSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 240, height: 160)
}
