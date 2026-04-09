// Views/Sidebar/TagsSidebarSection.swift
// Grove

import SwiftUI

/// The TAGS section of the sidebar.
struct TagsSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    // MARK: - Sheet / Alert State

    @State private var isShowingCreateBranch = false
    @State private var createBranchFromTag: String?

    @State private var isShowingDeleteAlert = false
    @State private var tagToDelete: TagInfo?

    var body: some View {
        Section(header: SidebarSectionHeader(title: "Tags")) {
            ForEach(viewModel.tags) { tag in
                tagRow(tag)
            }
        }
        .sheet(isPresented: $isShowingCreateBranch) {
            CreateBranchDialogView(
                repository: viewModel.repository,
                localBranches: viewModel.localBranches,
                fromRef: createBranchFromTag
            ) { _ in
                Task { await viewModel.refresh() }
            }
        }
        .alert(
            "Delete Tag",
            isPresented: $isShowingDeleteAlert,
            presenting: tagToDelete
        ) { tag in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteTag(tag) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { tag in
            Text("Delete tag \"\(tag.name)\"? This cannot be undone.")
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: TagInfo) -> some View {
        Label {
            HStack {
                Text(tag.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if tag.isAnnotated {
                    Spacer()
                    Image(systemName: "tag.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "tag")
                .foregroundStyle(.orange)
        }
        .tag(SidebarItem.tag(tag))
        .contextMenu {
            Button("Create Branch at \"\(tag.name)\"...") {
                createBranchFromTag = tag.name
                isShowingCreateBranch = true
            }
            Divider()
            Button("Delete Tag \"\(tag.name)\"...", role: .destructive) {
                tagToDelete = tag
                isShowingDeleteAlert = true
            }
        }
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.tags = MockData.tags

    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        TagsSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 220, height: 160)
}
