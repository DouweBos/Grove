---
"grove": minor
---

- Diffs stay fast at 100,000 lines, also with Wrap Lines, and can be shown side by side. Added, deleted, renamed and untracked files can be staged, unstaged and discarded by hunk and line. Click a line to select it, Shift- or Command-click for more; drag along a line to copy part of it.
- GroveUIKit, for apps that use GroveKit: a new product with Grove's git UI, starting with its style, feature checks and primitives. GroveKit adds `GitCommandPerforming`, push tag options, squash merge, stash keep-index and branch, and remote rename and prune. The refs, reflog, branches review and stash view models run their changes, and their undo, through their `commands`, which an app can set.
- GroveKit: `FileStatus.supportsHunkActions` says which changes can be staged by hunk and line, and the diff's models can be used off the main actor.
- GroveUIKit adds the diff: `GitDiffPane` and `GitDiffView` with unified and split layouts, word and syntax highlights, Wrap Lines, image and Git LFS diffs, hunk and line actions, and slots for an app's own rows and controls. An app's copy, toast and open-file come in through `GitUIHost`.
- GroveKit's `GitCommand` adds pushing a branch that isn't checked out (`pushBranch`), `sync`, `renameCurrentBranch`, and checking out after stashing or discarding changes; `.fetch(remote: nil)` fetches every remote, and a snapshot with nothing to save throws `GitCommandError.nothingToSnapshot`. `GitFeature` adds `verifySignatures` and `recurseSubmodules`, which pulls and pushes with those options need. Apps that switch over either enum need the new cases.
