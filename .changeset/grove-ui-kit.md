---
"grove": minor
---

- GroveUIKit, for apps that use GroveKit: a new product with Grove's git UI, starting with its style, feature checks and primitives. GroveKit adds `GitCommandPerforming`, push tag options, squash merge, stash keep-index and branch, and remote rename and prune. The refs, reflog, branches review and stash view models run their changes, and their undo, through their `commands`, which an app can set.
- GroveKit: `FileStatus.supportsHunkActions` says which changes can be staged by hunk and line, and the diff's models can be used off the main actor.
- GroveUIKit adds the diff: `GitDiffPane` and `GitDiffView` with unified and split layouts, word and syntax highlights, Wrap Lines, image and Git LFS diffs, hunk and line actions, and slots for an app's own rows and controls. An app's copy, toast and open-file come in through `GitUIHost`.
