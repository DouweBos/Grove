// Utilities/HomePath.swift
// Grove

import Foundation

/// `~/Projects/x` instead of `/Users/me/Projects/x`.
func abbreviatingHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
