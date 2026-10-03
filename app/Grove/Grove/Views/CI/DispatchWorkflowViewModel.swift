// Views/CI/DispatchWorkflowViewModel.swift
// Grove

import Foundation
import GroveKit
import Observation

/// The "Run Workflow" sheet: a workflow, the branch or tag to run it on, and the inputs its definition asks for.
@MainActor
@Observable
final class DispatchWorkflowViewModel: Identifiable {

    /// What the sheet shows under the workflow and ref.
    enum Form: Equatable {
        case loading
        case notDispatchable
        case inputs([CIDispatchInput])
        /// The definition couldn't be read or understood, so inputs are typed as name and value.
        case freeForm
    }

    struct FreeFormRow: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    let id = UUID()
    private(set) var workflows: [CIWorkflow]
    private(set) var workflowID: Int?
    private(set) var ref = ""
    private(set) var form = Form.loading
    /// Values by input name, starting at each input's default.
    private(set) var values: [String: String] = [:]
    private(set) var freeFormRows: [FreeFormRow] = []
    private(set) var progressTitle: String?
    private(set) var errorMessage: String?
    /// Remembered between runs, since whoever wants to hear about one usually wants it for the next.
    private(set) var notifiesWhenFinished = UserDefaults.standard.bool(forKey: DispatchWorkflowViewModel.notifiesKey)
    static let notifiesKey = "CINotifyWhenDispatchedRunFinishes"

    let repository: any GitRepositoryProtocol
    let refs: RepositoryRefs
    /// Called once the host accepted the dispatch.
    var onDispatched: ((CIDispatch) async -> Void)?

    init(repository: any GitRepositoryProtocol, refs: RepositoryRefs, workflows: [CIWorkflow] = [], workflowID: Int? = nil) {
        self.repository = repository
        self.refs = refs
        self.workflows = workflows.filter(\.isEnabled)
        self.workflowID = workflowID
    }

    // MARK: Derived

    var workflow: CIWorkflow? { workflows.first { $0.id == workflowID } }

    /// The remote runs are read from: origin when there is one.
    var remote: String { HostedRemoteResolver.location(of: refs.remotes)?.remote ?? refs.remotes.first?.name ?? "origin" }

    /// Branches on the remote, then tags: the refs the host can run a workflow on.
    var refCandidates: [String] {
        let prefix = remote + "/"
        let branches = refs.remoteBranches.filter { $0.name.hasPrefix(prefix) && $0.name != prefix + "HEAD" }
            .map { String($0.name.dropFirst(prefix.count)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return branches + refs.tags.map(\.name)
    }

    var inputs: [CIDispatchInput] {
        if case .inputs(let inputs) = form { return inputs }
        return []
    }

    var isSubmitting: Bool { progressTitle != nil }

    var canSubmit: Bool {
        guard !isSubmitting, workflow != nil, !ref.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch form {
        case .loading, .notDispatchable: return false
        case .freeForm: return true
        case .inputs(let inputs): return inputs.allSatisfy { !$0.isRequired || !(values[$0.name] ?? "").isEmpty }
        }
    }

    var dispatch: CIDispatch? {
        guard let workflowID else { return nil }
        let sent: [String: String]
        if form == .freeForm {
            sent = Dictionary(freeFormRows.filter { !$0.name.isEmpty }.map { ($0.name, $0.value) }) { $1 }
        } else {
            // An empty optional input is left out so the workflow sees its own default.
            sent = values.filter { name, value in !value.isEmpty && inputs.contains { $0.name == name } }
        }
        return CIDispatch(workflowID: workflowID, ref: ref.trimmingCharacters(in: .whitespaces), inputs: sent)
    }

    // MARK: Loading

    /// Picks the workflow and ref (the checked-out branch when it's on the remote, else the remote's default), then reads the inputs.
    func load() async {
        if !refs.hasLoaded { await refs.loadIfNeeded() }
        if workflows.isEmpty {
            do {
                workflows = try await repository.ciWorkflows().filter(\.isEnabled)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if workflow == nil { workflowID = workflows.first?.id }
        if ref.isEmpty {
            let candidates = refCandidates
            if let current = repository.currentBranch?.name, candidates.contains(current) {
                ref = current
            } else {
                ref = await repository.defaultBranch(of: remote) ?? candidates.first ?? ""
            }
        }
        await loadForm()
    }

    private func loadForm() async {
        guard let workflow, !ref.isEmpty else { return form = workflows.isEmpty ? .notDispatchable : .freeForm }
        let (path, ref) = (workflow.path, ref)
        form = .loading
        let parsed: Form
        do {
            switch WorkflowDispatchParser.parse(try await repository.ciWorkflowFile(path: path, ref: ref)) {
            case .notDispatchable: parsed = .notDispatchable
            case .inputs(let inputs): parsed = .inputs(inputs)
            case .unreadable: parsed = .freeForm
            }
        } catch {
            parsed = .freeForm
        }
        // The pickers may have moved on while the file was read.
        guard path == self.workflow?.path, ref == self.ref else { return }
        form = parsed
        values = Dictionary(inputs.map { ($0.name, $0.defaultValue) }) { $1 }
        if parsed == .freeForm, freeFormRows.isEmpty { freeFormRows = [FreeFormRow()] }
    }

    // MARK: Editing

    func setWorkflow(_ id: Int?) async {
        guard id != workflowID else { return }
        workflowID = id
        await loadForm()
    }

    /// The ref is typed freely; the inputs are only re-read for a ref that exists, not for every keystroke.
    func setRef(_ name: String) async {
        guard name != ref else { return }
        ref = name
        if refCandidates.contains(name) { await loadForm() }
    }

    func setValue(_ value: String, for input: CIDispatchInput) {
        values[input.name] = value
    }

    func value(for input: CIDispatchInput) -> String { values[input.name] ?? "" }

    func addFreeFormRow() {
        freeFormRows.append(FreeFormRow())
    }

    func removeFreeFormRow(_ row: FreeFormRow) {
        freeFormRows.removeAll { $0.id == row.id }
    }

    func setFreeFormRow(_ row: FreeFormRow, name: String? = nil, value: String? = nil) {
        guard let index = freeFormRows.firstIndex(where: { $0.id == row.id }) else { return }
        if let name { freeFormRows[index].name = name }
        if let value { freeFormRows[index].value = value }
    }

    // MARK: Submitting

    func setNotifiesWhenFinished(_ isOn: Bool) {
        notifiesWhenFinished = isOn
        UserDefaults.standard.set(isOn, forKey: Self.notifiesKey)
    }

    func submit() async {
        guard canSubmit, let dispatch else { return }
        errorMessage = nil
        progressTitle = "Starting \(workflow?.name ?? "workflow")…"
        do {
            try await repository.dispatchCIWorkflow(dispatch)
            progressTitle = nil
            await onDispatched?(dispatch)
        } catch {
            progressTitle = nil
            errorMessage = error.localizedDescription
        }
    }
}
