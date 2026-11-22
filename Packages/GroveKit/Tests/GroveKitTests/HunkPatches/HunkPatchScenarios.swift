// HunkPatchScenarios.swift
// GroveKitTests
//
// The changes the patch matrix runs, each with the bytes that staging or taking back some of its lines must leave.

import Foundation

nonisolated struct PatchScenario: Sendable, CustomStringConvertible {
    enum Kind { case tracked, untracked, renamed }

    let name: String
    var kind = Kind.tracked
    var mode = "100644"
    /// The mode after the change, when the change includes a chmod.
    var changedMode: String?
    /// Nil when the file doesn't exist on that side.
    let before: String?
    let after: String?
    let selection: [String]
    /// `before` plus the selected lines; nil removes the file.
    let staged: String?
    /// `after` minus the selected lines; nil removes the file.
    let reverted: String?

    var description: String { name }

    static let all: [PatchScenario] = modified + untracked + added + deleted + renamed + executable + crlf + noNewline

    static let modified = [
        PatchScenario(name: "modified", before: "one\ntwo\nthree\nfour\nfive\n", after: "one\nTWO\nthree\nfour\nFIVE\n",
                      selection: ["-two", "+TWO"],
                      staged: "one\nTWO\nthree\nfour\nfive\n", reverted: "one\ntwo\nthree\nfour\nFIVE\n"),
        PatchScenario(name: "modified, only a deletion", before: "a\nb\nc\n", after: "A\nc\n",
                      selection: ["-b"], staged: "a\nc\n", reverted: "b\nA\nc\n"),
        PatchScenario(name: "modified, only an addition", before: "a\nc\n", after: "a\nB\nC\n",
                      selection: ["+B"], staged: "a\nc\nB\n", reverted: "a\nC\n"),
        PatchScenario(name: "modified, lines that look like headers", before: "top\n-- old\n", after: "top\n++ new\n@@ -1 +1 @@\n",
                      selection: ["+++ new"], staged: "top\n-- old\n++ new\n", reverted: "top\n@@ -1 +1 @@\n"),
        PatchScenario(name: "modified, emptied", before: "a\nb\n", after: "",
                      selection: ["-a"], staged: "b\n", reverted: "a\n"),
        PatchScenario(name: "modified, filled", before: "", after: "a\nb\n",
                      selection: ["+a"], staged: "a\n", reverted: "b\n"),
    ]

    static let untracked = [
        PatchScenario(name: "untracked", kind: .untracked, before: nil, after: "a\nb\nc\n",
                      selection: ["+b"], staged: "b\n", reverted: "a\nc\n"),
        PatchScenario(name: "untracked, every line selected", kind: .untracked, before: nil, after: "a\n\nb\n",
                      selection: ["+a", "+", "+b"], staged: "a\n\nb\n", reverted: nil),
    ]

    static let added = [
        PatchScenario(name: "added", before: nil, after: "a\nb\nc\n",
                      selection: ["+b"], staged: "b\n", reverted: "a\nc\n"),
        PatchScenario(name: "added, every line selected", before: nil, after: "a\nb\n",
                      selection: ["+a", "+b"], staged: "a\nb\n", reverted: nil),
    ]

    static let deleted = [
        PatchScenario(name: "deleted", before: "a\nb\nc\n", after: nil,
                      selection: ["-b"], staged: "a\nc\n", reverted: "b\n"),
        PatchScenario(name: "deleted, every line selected", before: "a\nb\n", after: nil,
                      selection: ["-a", "-b"], staged: nil, reverted: "a\nb\n"),
    ]

    static let renamed = [
        PatchScenario(name: "renamed", kind: .renamed,
                      before: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n",
                      after: "one\nTWO\nthree\nfour\nfive\nsix\nSEVEN\neight\n",
                      selection: ["-two", "+TWO"],
                      staged: "one\nTWO\nthree\nfour\nfive\nsix\nseven\neight\n",
                      reverted: "one\ntwo\nthree\nfour\nfive\nsix\nSEVEN\neight\n"),
        PatchScenario(name: "renamed, executable", kind: .renamed, mode: "100755",
                      before: "one\ntwo\nthree\nfour\nfive\nsix\n", after: "one\ntwo\nthree\nfour\nfive\nSIX",
                      selection: ["+SIX"],
                      staged: "one\ntwo\nthree\nfour\nfive\nsix\nSIX", reverted: "one\ntwo\nthree\nfour\nfive\n"),
    ]

    static let executable = [
        PatchScenario(name: "executable", mode: "100755", before: "one\ntwo\nthree\n", after: "one\nTWO\nthree\nfour\n",
                      selection: ["+four"], staged: "one\ntwo\nthree\nfour\n", reverted: "one\nTWO\nthree\n"),
        PatchScenario(name: "executable, made so by the change", changedMode: "100755",
                      before: "one\ntwo\n", after: "ONE\ntwo\nthree\n",
                      selection: ["+three"], staged: "one\ntwo\nthree\n", reverted: "ONE\ntwo\n"),
        PatchScenario(name: "executable, no longer so", mode: "100755", changedMode: "100644",
                      before: "one\ntwo\n", after: "ONE\ntwo\nthree\n",
                      selection: ["+three"], staged: "one\ntwo\nthree\n", reverted: "ONE\ntwo\n"),
        PatchScenario(name: "executable, untracked", kind: .untracked, mode: "100755", before: nil, after: "a\nb\n",
                      selection: ["+a"], staged: "a\n", reverted: "b\n"),
        PatchScenario(name: "executable, added", mode: "100755", before: nil, after: "a\nb\n",
                      selection: ["+b"], staged: "b\n", reverted: "a\n"),
        PatchScenario(name: "executable, deleted", mode: "100755", before: "a\nb\n", after: nil,
                      selection: ["-a"], staged: "b\n", reverted: "a\n"),
    ]

    static let crlf = [
        PatchScenario(name: "CRLF", before: "one\r\ntwo\r\nthree\r\n", after: "one\r\nTWO\r\nthree\r\nfour\r\n",
                      selection: ["+four\r"], staged: "one\r\ntwo\r\nthree\r\nfour\r\n", reverted: "one\r\nTWO\r\nthree\r\n"),
        PatchScenario(name: "CRLF, untracked", kind: .untracked, before: nil, after: "a\r\n\r\nb\r\n",
                      selection: ["+\r"], staged: "\r\n", reverted: "a\r\nb\r\n"),
        PatchScenario(name: "CRLF, added", before: nil, after: "a\r\nb\r\n",
                      selection: ["+a\r"], staged: "a\r\n", reverted: "b\r\n"),
        PatchScenario(name: "CRLF, deleted", before: "a\r\nb\r\n", after: nil,
                      selection: ["-b\r"], staged: "a\r\n", reverted: "b\r\n"),
        PatchScenario(name: "CRLF, replacing LF", before: "a\nb\n", after: "a\r\nb\r\n",
                      selection: ["-b", "+b\r"], staged: "a\nb\r\n", reverted: "b\na\r\n"),
    ]

    static let noNewline = [
        PatchScenario(name: "no newline", before: "one\ntwo\nthree", after: "one\ntwo\nTHREE\nfour",
                      selection: ["+four"], staged: "one\ntwo\nthree\nfour", reverted: "one\ntwo\nTHREE\n"),
        PatchScenario(name: "no newline, taking out the last line", before: "one\ntwo\nthree", after: "one\ntwo\nTHREE\nfour",
                      selection: ["-three"], staged: "one\ntwo\n", reverted: "one\ntwo\nthree\nTHREE\nfour"),
        PatchScenario(name: "no newline, gained", before: "one\ntwo", after: "one\ntwo\n",
                      selection: ["+two"], staged: "one\ntwo\ntwo\n", reverted: "one\n"),
        PatchScenario(name: "no newline, lost", before: "one\ntwo\n", after: "one\ntwo",
                      selection: ["-two"], staged: "one\n", reverted: "one\ntwo\ntwo"),
        PatchScenario(name: "no newline, context", before: "one\ntwo\nlast", after: "ONE\ntwo\nlast",
                      selection: ["-one"], staged: "two\nlast", reverted: "one\nONE\ntwo\nlast"),
        PatchScenario(name: "no newline, appended to", before: "one\ntwo", after: "one\ntwo\nthree\n",
                      selection: ["+three"], staged: "one\ntwo\nthree\n", reverted: "one\ntwo\n"),
        PatchScenario(name: "no newline, untracked", kind: .untracked, before: nil, after: "a\nb",
                      selection: ["+b"], staged: "b", reverted: "a\n"),
        PatchScenario(name: "no newline, added", before: nil, after: "a\nb",
                      selection: ["+a"], staged: "a\n", reverted: "b"),
        PatchScenario(name: "no newline, deleted", before: "a\nb", after: nil,
                      selection: ["-a"], staged: "b", reverted: "a\n"),
        PatchScenario(name: "no newline, CRLF", before: "one\r\ntwo", after: "one\r\ntwo\r\nthree",
                      selection: ["+three"], staged: "one\r\ntwo\nthree", reverted: "one\r\ntwo\r\n"),
    ]
}
