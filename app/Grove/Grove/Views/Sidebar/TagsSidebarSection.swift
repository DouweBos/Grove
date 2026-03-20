// Views/Sidebar/TagsSidebarSection.swift
// Grove

import SwiftUI

/// The TAGS section of the sidebar.
struct TagsSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    var body: some View {
        Section(header: SidebarSectionHeader(title: "Tags")) {
            ForEach(viewModel.tags) { tag in
                tagRow(tag)
            }
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
            Button("Create Branch at \"\(tag.name)\"...") { }
            Divider()
            Button("Delete Tag \"\(tag.name)\"...", role: .destructive) { }
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
