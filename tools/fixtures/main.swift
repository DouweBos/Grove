// main.swift
// tools/fixtures
//
// CLI entry for make-fixture.sh; the generator itself lives in app/Grove/GroveTests/Fixtures so tests share it.

import Foundation

let usage = """
usage: make-fixture.sh <out-dir> [--preset small|medium|large] [--seed N] [--force]
         [--commits N] [--branches N] [--remote-branches N] [--tags N] [--worktrees N] [--submodules N] [--files N]
         [--dirty N] [--merge-conflict] [--rebase-conflict] [--detached] [--diverged] [--no-upstream]
         [--missing-worktree] [--stashes N] [--large-file] [--binary-image]
"""

func fail(_ message: String, showUsage: Bool = true) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n\(showUsage ? "\n" + usage + "\n" : "")".utf8))
    exit(1)
}

/// Fixtures may only be written to temporary locations, never next to real repositories.
func isTemporary(_ url: URL) -> Bool {
    let path = url.resolvingSymlinksInPath().path
    let roots = ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/",
                 FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/"]
    return roots.contains { path.hasPrefix($0) }
}

var args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first, !first.hasPrefix("-") else { fail("missing <out-dir>") }
args.removeFirst()
let out = URL(fileURLWithPath: first).standardizedFileURL
guard isTemporary(out) else { fail("\(out.path) is not under /tmp or $TMPDIR") }

var preset = FixturePreset.small
if let index = args.firstIndex(of: "--preset"), index + 1 < args.count {
    guard let parsed = FixturePreset(rawValue: args[index + 1]) else { fail("unknown preset \(args[index + 1])") }
    preset = parsed
    args.removeSubrange(index...index + 1)
}
var spec = FixtureSpec(preset)
var force = false
var cursor = 0

func number() -> Int {
    cursor += 1
    guard cursor < args.count, let value = Int(args[cursor]), value >= 0 else { fail("\(args[cursor - 1]) needs a number") }
    return value
}

while cursor < args.count {
    switch args[cursor] {
    case "--seed": spec.seed = UInt64(number())
    case "--force": force = true
    case "--commits": spec.commits = number()
    case "--branches": spec.branches = number()
    case "--remote-branches": spec.remoteBranches = number()
    case "--tags": spec.tags = number()
    case "--worktrees": spec.worktrees = number()
    case "--submodules": spec.submodules = number()
    case "--files": spec.files = number()
    case "--dirty": spec.states.append(.dirty(number()))
    case "--stashes": spec.states.append(.stashes(number()))
    case "--merge-conflict": spec.states.append(.mergeConflict)
    case "--rebase-conflict": spec.states.append(.rebaseConflict)
    case "--detached": spec.states.append(.detached)
    case "--diverged": spec.states.append(.diverged)
    case "--no-upstream": spec.states.append(.noUpstream)
    case "--missing-worktree": spec.states.append(.missingWorktree)
    case "--large-file": spec.states.append(.largeFile)
    case "--binary-image": spec.states.append(.binaryImage)
    case "-h", "--help": print(usage); exit(0)
    default: fail("unknown option \(args[cursor])")
    }
    cursor += 1
}

let manager = FileManager.default
if force, manager.fileExists(atPath: out.path) {
    let contents = (try? manager.contentsOfDirectory(atPath: out.path)) ?? []
    guard contents.isEmpty || contents.contains(FixtureGenerator.markerName) else {
        fail("--force only replaces fixture directories; \(out.path) has no \(FixtureGenerator.markerName)")
    }
    try manager.removeItem(at: out)
}

do {
    let result = try FixtureGenerator(spec: spec, root: out).generate()
    print("fixture:     \(spec.preset.rawValue), seed \(spec.seed)\(spec.states.isEmpty ? "" : ", " + spec.states.map(\.label).joined(separator: " "))")
    print(result.summary)
} catch {
    fail(error.localizedDescription, showUsage: false)
}
