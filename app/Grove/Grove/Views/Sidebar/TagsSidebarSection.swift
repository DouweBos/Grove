// Views/Sidebar/TagsSidebarSection.swift
// Grove

import SwiftUI

/// Tags, collapsed by default since repositories often have many. Hidden when there are none.
struct TagsSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    @State private var isExpanded = false
    @State private var createFromRef: CreateBranchRequest?
    @State private var tagToDelete: TagInfo?

    var body: some View {
        if !viewModel.tags.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(viewModel.tags) { tagRow($0) }
            } header: {
                SidebarSectionHeader(title: "Tags", count: viewModel.tags.count)
            }
            .sheet(item: $createFromRef) { request in
                CreateBranchDialogView(
                    repository: viewModel.repository,
                    localBranches: viewModel.localBranches,
                    fromRef: request.ref
                ) { _ in
                    Task { await viewModel.didChangeRepository() }
                }
            }
            .confirmationDialog(
                "Delete the tag \u{201C}\(tagToDelete?.name ?? "")\u{201D}?",
                isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }),
                presenting: tagToDelete
            ) { tag in
                Button("Delete Tag", role: .destructive) {
                    Task { await viewModel.deleteTag(tag) }
                }
            } message: { _ in
                Text("Only the local tag is deleted; a pushed copy stays on the remote.")
            }
        }
    }

    private func tagRow(_ tag: TagInfo) -> some View {
        SidebarRow(title: tag.name, symbol: tag.isAnnotated ? "tag.fill" : "tag", tint: Theme.warning)
            .tag(SidebarItem.tag(tag))
            .draggable(tag.name)
            .contextMenu {
                Button("New Branch from \u{201C}\(tag.name)\u{201D}…", systemImage: "arrow.triangle.branch") {
                    createFromRef = CreateBranchRequest(ref: tag.name)
                }
                Button("Copy Name", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tag.name, forType: .string)
                }
                Button("Reveal in History", systemImage: "clock.arrow.circlepath") { viewModel.revealInHistory(.tag(tag)) }
                Divider()
                Button("Delete Tag…", systemImage: "trash", role: .destructive) {
                    tagToDelete = tag
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
