// Views/CI/CIRunFilterBar.swift
// Grove

import GroveKit
import SwiftUI

/// Workflow, branch and status filters above the run list; each re-reads the list from the host.
struct CIRunFilterBar: View {
    @Environment(CIViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Picker("Workflow", selection: Binding(get: { viewModel.query.workflowID },
                                                  set: { id in Task { await viewModel.setWorkflowFilter(id) } })) {
                Text("All Workflows").tag(Int?.none)
                Divider()
                ForEach(viewModel.workflows) { Text($0.name).tag(Int?.some($0.id)) }
            }
            HStack(spacing: Theme.Spacing.xs) {
                Picker("Branch", selection: Binding(get: { viewModel.query.branch },
                                                    set: { branch in Task { await viewModel.setBranchFilter(branch) } })) {
                    Text("All Branches").tag(String?.none)
                    Divider()
                    ForEach(viewModel.branchCandidates, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Status", selection: Binding(get: { viewModel.query.status },
                                                    set: { status in Task { await viewModel.setStatusFilter(status) } })) {
                    Text("Any Status").tag(CIRunStatus?.none)
                    Divider()
                    ForEach(CIRunStatus.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag(CIRunStatus?.some($0)) }
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let vm = CIViewModel(repository: MockGitRepository())
    return CIRunFilterBar()
        .environment(vm)
        .padding()
        .frame(width: 360)
        .background(Theme.surface)
        .task { await vm.refresh() }
}
