---
"grove": minor
---

GroveKit, for apps that use it:
- `ShellResult` has a public initializer, and `GitRunner`'s defaults are nonisolated, so runners outside GroveKit build without spelling them out.
- `DiffParser.parse(_:)` and `DiffParser.fileDiffs(patch:nameStatus:)` are public, as are `DiffResult` and `FileDiff` initializers.
- `diff(from:to:)` diffs two revisions. Breaking: it is a new `GitRepositoryProtocol` requirement, so other conformers add it.
- `BlameViewModel.open(file:revision:)` blames a file at any ref.
- `CommitGraphBuilder.append(_:)` adds a page of commits to the graph without rebuilding it.
- Public `ListSelection.init()` and `focus`, `WorkingCopyViewModel.selectedPath`, `PendingHunkDiscard.action` and `RestackPlan.steps`; `PullRequestHost.headRef(number:)`'s default is nonisolated.
- `RefName.isValid(_:)` validates ref names and `BranchTreeNode.build(_:)` nests branches into folders. Breaking: `ReflogViewModel.isValidBranchName(_:)` is now `RefName.isValid(_:)`.
- `RefActionsViewModel` runs branch, tag, remote, submodule and worktree actions (checkout, rename, delete, merge, rebase, tracking, worktree removal) with undo records, so apps no longer rebuild them.
- `GitRepository(path:runner:hosting:naming:)` takes a `GitNaming` for its scratch files, the restack plan's folder and the branch-parent config key; it defaults to `grovekit` names. Pass `GitNaming(name: "grove")` to share restacks and branch parents with Grove.
- `ViewModelPreferences.store` and `keyPrefix` (default `grovekit.`) keep the view models' settings apart from an app's own. `HostingError` messages no longer mention Grove or its Settings.
