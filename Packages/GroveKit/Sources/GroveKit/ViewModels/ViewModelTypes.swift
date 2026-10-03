// ViewModels/ViewModelTypes.swift
// GroveKit
//
// Small value types the view models hand to the app's views.

import Foundation

/// The set of operations the user can invoke from a hunk header.
public enum HunkAction {
    case stageHunk
    case unstageHunk
    case discardHunk
    case stageLines
    case unstageLines
    case discardLines
}

/// Where a commit stands against the branch's upstream.
public enum CommitSyncState {
    case incoming, outgoing

    public var symbol: String { self == .incoming ? "arrow.down.left" : "arrow.up.right" }
    public var label: String { self == .incoming ? "Not pulled yet" : "Not pushed yet" }
}

/// How History lists commits.
public enum HistoryLayout: String, CaseIterable, Identifiable {
    case graph, table

    public var id: Self { self }
    public var title: String { self == .graph ? "Graph" : "Table" }
    public var symbol: String { self == .graph ? "point.3.connected.trianglepath.dotted" : "tablecells" }
}

/// The view model settings an app's preferences expose, kept in the standard user defaults.
public enum ViewModelPreferences {

    enum Key {
        static let warnOnHunkDiscard = "warnOnHunkDiscard"
        static let historyLayout = "historyLayout"
        static let staleBranchDays = "staleBranchDays"
    }

    private static var defaults: UserDefaults { .standard }

    /// Ask before discarding a hunk or lines.
    public static var warnOnHunkDiscard: Bool {
        get { defaults.object(forKey: Key.warnOnHunkDiscard) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.warnOnHunkDiscard) }
    }

    /// Days without commits before Branches Review calls a branch stale.
    public static var staleBranchDays: Int {
        max(1, defaults.object(forKey: Key.staleBranchDays) as? Int ?? 90)
    }

    public static var historyLayout: HistoryLayout {
        get { HistoryLayout(rawValue: defaults.string(forKey: Key.historyLayout) ?? "") ?? .graph }
        set { defaults.set(newValue.rawValue, forKey: Key.historyLayout) }
    }
}

/// Names for exported files.
public enum ExportName {
    /// A file-name-safe version of a commit subject or ref name.
    public static func slug(_ text: String, limit: Int = 50) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let words = text.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return String(words.joined(separator: "-").prefix(limit))
    }
}
