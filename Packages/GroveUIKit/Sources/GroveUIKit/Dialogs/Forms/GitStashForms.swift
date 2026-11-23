// Dialogs/Forms/GitStashForms.swift
// GroveUIKit
//
// Stashes, snapshots, tags and remotes.

#if os(macOS)
import Foundation
import GroveKit

public struct GitStashForm: GitDialogForm, Equatable {
    public var message = ""
    public var includeUntracked = true
    /// What's staged stays in the working copy too.
    public var keepIndex = false
    public var selectFiles = false
    public var paths: Set<String> = []

    public init(paths: [String]? = nil) {
        if let paths, !paths.isEmpty {
            self.paths = Set(paths)
            selectFiles = true
        }
    }

    public var commands: [GitCommand] {
        guard !selectFiles || !paths.isEmpty else { return [] }
        return [.stash(message: message.trimmed.isEmpty ? nil : message.trimmed, includeUntracked: includeUntracked,
                       keepIndex: keepIndex, paths: selectFiles ? paths.sorted() : nil)]
    }
}

public struct GitSnapshotForm: GitDialogForm, Equatable {
    public var message: String
    public var includeUntracked = true

    public init(branch: String?, date: Date = .now) {
        message = Self.defaultMessage(branch: branch, date: date)
    }

    public static func defaultMessage(branch: String?, date: Date = .now) -> String {
        "Snapshot of \(branch ?? "HEAD"), \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    public var commands: [GitCommand] {
        message.trimmed.isEmpty ? [] : [.snapshot(message: message.trimmed, includeUntracked: includeUntracked)]
    }
}

public struct GitStashBranchForm: GitDialogForm, Equatable {
    public let index: Int
    public var name = ""

    public init(index: Int) {
        self.index = index
    }

    public var commands: [GitCommand] {
        RefName.isValid(name.trimmed) ? [.branchFromStash(index: index, name: name.trimmed)] : []
    }
}

public struct GitTagForm: GitDialogForm, Equatable {
    public var name = ""
    /// A branch, tag or commit; HEAD when empty.
    public var target: String
    /// Stores a message, author and date with the tag.
    public var annotated = false
    public var message = ""

    public init(target: String?) {
        self.target = target ?? "HEAD"
    }

    public var commands: [GitCommand] {
        guard RefName.isValid(name.trimmed) else { return [] }
        let at = target.trimmed
        return [.createTag(name: name.trimmed, at: at.isEmpty || at == "HEAD" ? nil : at,
                           message: annotated && !message.trimmed.isEmpty ? message : nil, sign: false)]
    }
}

public struct GitRemoteForm: GitDialogForm, Equatable {
    /// Nil adds a remote.
    public let original: RemoteInfo?
    public var name: String
    public var url: String

    public init(remote: RemoteInfo?, existing: [RemoteInfo]) {
        original = remote
        name = remote?.name ?? (existing.contains { $0.name == "origin" } ? "" : "origin")
        url = remote?.url ?? ""
    }

    /// Why `name` can't be used, or nil when it can.
    public func nameProblem(existing: [RemoteInfo]) -> String? {
        let name = name.trimmed
        if name.isEmpty { return "Enter a name." }
        if name.contains(where: \.isWhitespace) { return "Names can\u{2019}t contain spaces." }
        if !RefName.isValid(name) { return "\u{201C}\(name)\u{201D} isn\u{2019}t a name git accepts." }
        if name != original?.name, existing.contains(where: { $0.name == name }) { return "\u{201C}\(name)\u{201D} already exists." }
        return nil
    }

    public var commands: [GitCommand] {
        let name = name.trimmed, url = url.trimmed
        guard !name.isEmpty, !url.isEmpty else { return [] }
        guard let original else { return [.addRemote(name: name, url: url)] }
        var result: [GitCommand] = []
        if name != original.name { result.append(.renameRemote(from: original.name, to: name)) }
        if url != original.url { result.append(.setRemoteURL(url, remote: name)) }
        return result
    }
}
#endif
