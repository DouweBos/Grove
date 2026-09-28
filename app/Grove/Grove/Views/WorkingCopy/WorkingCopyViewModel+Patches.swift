// Views/WorkingCopy/WorkingCopyViewModel+Patches.swift
// Grove
//
// Create Patch from selected changes and Apply Patch, which checks the patch before applying it.

import Foundation

/// A patch file chosen for Apply Patch, with the result of `git apply --check`.
struct PatchApplyRequest: Identifiable {
    enum Check: Equatable {
        case checking
        case applies
        case fails(String)
    }

    let file: URL
    var toIndex = false
    var check = Check.checking
    var isApplying = false

    var id: URL { file }
    var canApply: Bool { check == .applies && !isApplying }
}

extension WorkingCopyViewModel {

    /// The rows of one section a patch is made from: the selection in that section, else the clicked row.
    func patchEntries(for entry: StatusEntry, side: DiffSide) -> [StatusEntry] {
        let row = FileRow(path: entry.path, side: side)
        guard fileSelection.contains(row) else { return [entry] }
        let paths = Set(fileSelection.rows.filter { $0.side == side }.map(\.path))
        return statusEntries.filter { paths.contains($0.path) }
    }

    /// The selection's rows on the focused row's side, for the Files panel menu.
    var selectionForPatch: (entries: [StatusEntry], side: DiffSide)? {
        guard let focus = fileSelection.focus, let entry = statusEntries.first(where: { $0.path == focus.path }),
              !entry.isConflicted else { return nil }
        return (patchEntries(for: entry, side: focus.side), focus.side)
    }

    func suggestedPatchName(for entries: [StatusEntry]) -> String {
        if entries.count == 1, let entry = entries.first { return entry.fileName + ".patch" }
        let branch = (repository.currentBranch?.name ?? "changes").replacingOccurrences(of: "/", with: "-")
        return branch + ".patch"
    }

    func createPatch(from entries: [StatusEntry], side: DiffSide, to url: URL) async {
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
    func requestPatchFile() {
        isChoosingPatch = true
    }

    func setChoosingPatch(_ choosing: Bool) {
        isChoosingPatch = choosing
    }

    func beginApplyPatch(_ file: URL) async {
        isChoosingPatch = false
        patchApply = PatchApplyRequest(file: file)
        await checkPendingPatch()
    }

    /// The index check differs (the index must match too), so it re-runs.
    func setPatchAppliesToIndex(_ toIndex: Bool) async {
        guard patchApply?.toIndex != toIndex else { return }
        patchApply?.toIndex = toIndex
        await checkPendingPatch()
    }

    func cancelApplyPatch() {
        patchApply = nil
    }

    func applyPendingPatch() async {
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
