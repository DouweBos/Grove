// Views/CI/DispatchWorkflowSheet.swift
// Grove

import SwiftUI

/// Starts a workflow by hand on a branch or tag, with the inputs its definition asks for.
struct DispatchWorkflowSheet: View {

    let viewModel: DispatchWorkflowViewModel
    let onCancel: () -> Void

    var body: some View {
        DialogSheet(
            title: "Run Workflow",
            message: "Starts \(viewModel.workflow?.name ?? "a workflow") on \(viewModel.ref.isEmpty ? "a branch or tag" : viewModel.ref).",
            symbol: "play.circle",
            width: 520,
            progress: viewModel.progressTitle,
            errorMessage: viewModel.errorMessage,
            primaryTitle: "Run",
            isPrimaryDisabled: !viewModel.canSubmit,
            onCancel: onCancel,
            onPrimary: { Task { await viewModel.submit() } }
        ) {
            DialogCard {
                DialogField("Workflow") {
                    Picker("Workflow", selection: Binding(get: { viewModel.workflowID },
                                                          set: { id in Task { await viewModel.setWorkflow(id) } })) {
                        ForEach(viewModel.workflows) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                    .labelsHidden()
                }
                DialogField("Branch or Tag") {
                    ComboBox(text: Binding(get: { viewModel.ref }, set: { name in Task { await viewModel.setRef(name) } }),
                             items: viewModel.refCandidates, placeholder: "main", isMonospaced: true)
                }
            }
            form
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var form: some View {
        switch viewModel.form {
        case .loading:
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Reading the workflow\u{2019}s inputs\u{2026}").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        case .notDispatchable:
            Banner(symbol: "hand.raised", message: viewModel.workflows.isEmpty
                   ? "This repository has no workflows to run."
                   : "This workflow can\u{2019}t be started by hand: it has no workflow_dispatch trigger on \(viewModel.ref).")
        case .inputs(let inputs):
            if !inputs.isEmpty {
                DialogCard { ForEach(inputs) { DispatchInputField(viewModel: viewModel, input: $0) } }
            }
        case .freeForm:
            DialogCard {
                Text("Grove couldn\u{2019}t read this workflow\u{2019}s inputs. Add the ones it needs by name.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(viewModel.freeFormRows) { row in
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("Name", text: Binding(get: { row.name }, set: { viewModel.setFreeFormRow(row, name: $0) }))
                            .font(.monoCaption)
                            .frame(width: 160)
                        TextField("Value", text: Binding(get: { row.value }, set: { viewModel.setFreeFormRow(row, value: $0) }))
                        Button { viewModel.removeFreeFormRow(row) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove Input")
                    }
                    .textFieldStyle(.roundedBorder)
                }
                Button("Add Input", systemImage: "plus") { viewModel.addFreeFormRow() }
                    .buttonStyle(.borderless)
            }
        }
    }
}

/// One typed input: a checkbox, a menu of choices, or a text field, with its description underneath.
private struct DispatchInputField: View {
    let viewModel: DispatchWorkflowViewModel
    let input: CIDispatchInput

    private var text: Binding<String> {
        Binding(get: { viewModel.value(for: input) }, set: { viewModel.setValue($0, for: input) })
    }

    var body: some View {
        if input.kind == .boolean {
            DialogOptionRow(isOn: Binding(get: { viewModel.value(for: input) == "true" },
                                          set: { viewModel.setValue($0 ? "true" : "false", for: input) }),
                            label: input.name, description: input.description.isEmpty ? nil : input.description)
                .padding(.leading, 96 + Theme.Spacing.md)
        } else {
            DialogField(input.isRequired ? "\(input.name) *" : input.name) {
                VStack(alignment: .leading, spacing: 3) {
                    control
                    if !input.description.isEmpty {
                        Text(input.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch input.kind {
        case .choice(let options):
            Picker(input.name, selection: text) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        case .number:
            TextField("Number", text: text).textFieldStyle(.roundedBorder).font(.monoCaption)
        case .environment:
            TextField("Environment name", text: text).textFieldStyle(.roundedBorder)
        case .string, .boolean:
            TextField(input.isRequired ? "Required" : "Optional", text: text).textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    let repo = MockGitRepository()
    let refs = RepositoryRefs(repository: repo)
    refs.replace(remoteBranches: MockData.branches.filter(\.isRemote), remotes: MockData.remotes)
    return DispatchWorkflowSheet(viewModel: DispatchWorkflowViewModel(repository: repo, refs: refs, workflows: MockData.ciWorkflows,
                                                                      workflowID: 2)) {}
}
