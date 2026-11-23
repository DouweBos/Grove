// History/Compare/CompareModel.swift
// GroveUIKit

#if os(macOS)
import Foundation
import GroveKit
import Observation

/// One `base...compare`: the commits only on each side, where they meet, whether merging would conflict,
/// and the files `compare` changed since they met.
@MainActor
@Observable
final class CompareModel {
    private(set) var comparison: BranchComparison?
    private(set) var preview = MergePreview()
    private(set) var files: [FileDiff] = []
    private(set) var isLoading = false
    private(set) var isLoadingFiles = false
    var errorMessage: String?
    private var loadedKey: String?
    /// Bumped per load, so a superseded one drops what it gets back.
    private var loadID = 0

    var isIdentical: Bool {
        guard let comparison else { return false }
        return comparison.onlyInBase.isEmpty && comparison.onlyInCompare.isEmpty && comparison.files.isEmpty
    }

    func load(_ repository: any GitRepositoryProtocol, base: String, compare: String) async {
        let key = "\(base)...\(compare)"
        if key != loadedKey {
            comparison = nil
            files = []
            preview = MergePreview()
        }
        loadedKey = key
        loadID += 1
        let id = loadID
        errorMessage = nil
        guard !base.isEmpty, !compare.isEmpty, base != compare else {
            comparison = nil
            return
        }
        isLoading = true
        isLoadingFiles = true
        async let preview = repository.mergePreview(base: base, compare: compare)
        do {
            let result = try await repository.compareBranches(base: base, compare: compare)
            guard loadID == id else { return }
            comparison = result
        } catch {
            guard loadID == id else { return }
            errorMessage = error.localizedDescription
        }
        if loadID == id { isLoading = false }
        let merge = await preview
        guard loadID == id else { return }
        self.preview = merge
        let diffs = try? await repository.diff(from: merge.mergeBase ?? base, to: compare)
        guard loadID == id else { return }
        files = diffs ?? []
        isLoadingFiles = false
    }
}
#endif
