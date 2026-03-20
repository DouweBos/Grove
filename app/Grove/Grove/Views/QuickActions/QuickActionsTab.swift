// Views/QuickActions/QuickActionsTab.swift
// Grove

import Foundation

// MARK: - QuickActionsTab

/// The two search-mode tabs available in the Quick Actions command palette.
enum QuickActionsTab: String, CaseIterable, Identifiable {

    /// Searches across sidebar navigation items, branch names, and commit SHAs.
    case items = "Items"

    /// Searches across file paths in the working tree and history.
    case filename = "Filename"

    // MARK: Identifiable

    var id: String { rawValue }
}
