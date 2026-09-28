// Views/Sidebar/SidebarViewModel+Submodules.swift
// Grove

import Foundation

extension SidebarViewModel {

    func initSubmodule(_ submodule: SubmoduleInfo) async {
        await perform("Cloning \(submodule.displayName)…") { try await repository.initSubmodule(path: submodule.path) }
    }

    func updateSubmodule(_ submodule: SubmoduleInfo, toRemote: Bool) async {
        await perform("Updating \(submodule.displayName)…") {
            try await repository.updateSubmodule(path: submodule.path, toRemote: toRemote)
        }
    }

    func fetchSubmodule(_ submodule: SubmoduleInfo) async {
        await perform("Fetching \(submodule.displayName)…") { try await repository.fetchSubmodule(path: submodule.path) }
    }

    func removeSubmodule(_ submodule: SubmoduleInfo) async {
        await perform("Removing \(submodule.displayName)…") { try await repository.removeSubmodule(path: submodule.path) }
    }

    /// Throws so the Add Submodule sheet can show the failure and stay open.
    func addSubmodule(url: String, path: String, branch: String?) async throws {
        do {
            try await repository.addSubmodule(url: url, path: path, branch: branch)
        } catch {
            await didChangeRepository()
            throw error
        }
        dismissAddSubmodule()
        await didChangeRepository()
    }

    /// `vendor/icons` for `https://github.com/example/icons.git`.
    static func suggestedSubmodulePath(for url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }
}
