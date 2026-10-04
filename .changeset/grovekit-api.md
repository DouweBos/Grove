---
"grove": minor
---

GroveKit, for apps that use it:
- `ShellResult` has a public initializer, and `GitRunner`'s defaults are nonisolated, so runners outside GroveKit build without spelling them out.
- `DiffParser.parse(_:)` and `DiffParser.fileDiffs(patch:nameStatus:)` are public, as are `DiffResult` and `FileDiff` initializers.
- `diff(from:to:)` diffs two revisions. Breaking: it is a new `GitRepositoryProtocol` requirement, so other conformers add it.
- `BlameViewModel.open(file:revision:)` blames a file at any ref.
- `CommitGraphBuilder.append(_:)` adds a page of commits to the graph without rebuilding it.
