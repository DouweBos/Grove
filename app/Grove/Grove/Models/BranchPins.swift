// Models/BranchPins.swift
// Grove

import Foundation

/// Branches pinned to the top of the sidebar, per repository; shared by the sidebar and the New Branch dialog.
enum BranchPins {
    static func key(forRepositoryAt path: String) -> String {
        "grove.pinnedBranches.\(path)"
    }

    static func names(forRepositoryAt path: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key(forRepositoryAt: path)) ?? [])
    }

    static func save(_ names: Set<String>, forRepositoryAt path: String) {
        UserDefaults.standard.set(Array(names).sorted(), forKey: key(forRepositoryAt: path))
    }

    static func pin(_ branch: String, inRepositoryAt path: String) {
        save(names(forRepositoryAt: path).union([branch]), forRepositoryAt: path)
    }
}
