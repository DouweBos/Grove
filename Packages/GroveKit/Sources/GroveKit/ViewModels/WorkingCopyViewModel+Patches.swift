// ViewModels/WorkingCopyViewModel+Patches.swift
// GroveKit
//
// Create Patch from selected changes and Apply Patch, which checks the patch before applying it.

import Foundation

/// A patch file chosen for Apply Patch, with the result of `git apply --check`.
public struct PatchApplyRequest: Identifiable {
    public enum Check: Equatable {
        case checking
        case applies
        case fails(String)
    }

    public let file: URL
    public var toIndex = false
    public var check = Check.checking
    public var isApplying = false

    public init(file: URL, toIndex: Bool = false, check: Check = Check.checking, isApplying: Bool = false) {
        self.file = file
        self.toIndex = toIndex
        self.check = check
        self.isApplying = isApplying
    }

    public var id: URL { file }
    public var canApply: Bool { check == .applies && !isApplying }
}

extension WorkingCopyViewModel {

    /// The rows of one section a patch is made from: the selection in that section, else the clicked row.
    public func patchEntries(for entry: StatusEntry, side: DiffSide) -> [StatusEntry] {
        let row = FileRow(path: entry.path, side: side)
        guard fileSelection.contains(row) else { return [entry] }
        let paths = Set(fileSelection.rows.filter { $0.side == side }.map(\.path))
        return statusEntries.filter { paths.contains($0.path) }
    }

    /// The selection's rows on the focused row's side, for the Files panel menu.
    public var selectionForPatch: (entries: [StatusEntry], side: DiffSide)? {
        guard let focus = fileSelection.focus, let entry = statusEntries.first(where: { $0.path == focus.path }),
              !entry.isConflicted else { return nil }
        return (patchEntries(for: entry, side: focus.side), focus.side)
    }

    public func suggestedPatchName(for entries: [StatusEntry]) -> String {
        if entries.count == 1, let entry = entries.first { return entry.fileName + ".patch" }
        let branch = (repository.currentBranch?.name ?? "changes").replacingOccurrences(of: "/", with: "-")
        return branch + ".patch"
    }

    public func createPatch(from entries: [StatusEntry], side: DiffSide, to url: URL) async {
        do {
            let patch = try await repository.patch(paths: entries.map(\.path), staged: side == .staged)
            guard !patch.isEmpty else {
                errorMessage = "The selected files have no textual changes to put in a patch."
                return
            }
            try Data(patch.utf8).write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Apply

    /// Asks the view to show the open panel, e.g. from File > Apply Patch.
    public func requestPatchFile() {
        isChoosingPatch = true
    }

    public func setChoosingPatch(_ choosing: Bool) {
        isChoosingPatch = choosing
    }

    public func beginApplyPatch(_ file: URL) async {
        isChoosingPatch = false
        patchApply = PatchApplyRequest(file: file)
        await checkPendingPatch()
    }

    /// The index check differs (the index must match too), so it re-runs.
    public func setPatchAppliesToIndex(_ toIndex: Bool) async {
        guard patchApply?.toIndex != toIndex else { return }
        patchApply?.toIndex = toIndex
        await checkPendingPatch()
    }

    public func cancelApplyPatch() {
        patchApply = nil
    }

    public func applyPendingPatch() async {
        guard let request = patchApply, request.canApply else { return }
        patchApply?.isApplying = true
        do {
            try await repository.applyPatch(at: request.file, toIndex: request.toIndex, checkOnly: false)
            patchApply = nil
        } catch {
            patchApply?.isApplying = false
            patchApply?.check = .fails(Self.patchFailure(error))
        }
        await repositoryChanged()
    }

    private func checkPendingPatch() async {
        guard let request = patchApply else { return }
        patchApply?.check = .checking
        let result: PatchApplyRequest.Check
        do {
            try await repository.applyPatch(at: request.file, toIndex: request.toIndex, checkOnly: true)
            result = .applies
        } catch {
            result = .fails(Self.patchFailure(error))
        }
        // The toggle may have flipped while this check ran.
        guard patchApply?.file == request.file, patchApply?.toIndex == request.toIndex else { return }
        patchApply?.check = result
    }

    private static func patchFailure(_ error: Error) -> String {
        if case GitRepositoryError.applyPatchFailed(let detail) = error, !detail.isEmpty { return detail }
        return error.localizedDescription
    }
}
