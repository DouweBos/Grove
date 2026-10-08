// Views/Sidebar/FolderExpansion.swift
// Grove

/// A sidebar folder opens for the checked-out branch and closes again once it leaves, e.g. when a stack read
/// lifts it out; a folder the user toggled stays as they left it.
struct FolderExpansion: Equatable {
    private(set) var isExpanded: Bool
    private var openedForHEAD: Bool

    init(containsHEAD: Bool) {
        isExpanded = containsHEAD
        openedForHEAD = containsHEAD
    }

    mutating func headChanged(contains: Bool) {
        if contains, !isExpanded {
            isExpanded = true
            openedForHEAD = true
        } else if !contains, openedForHEAD {
            isExpanded = false
            openedForHEAD = false
        }
    }

    mutating func toggle(to expanded: Bool) {
        isExpanded = expanded
        openedForHEAD = false
    }
}
