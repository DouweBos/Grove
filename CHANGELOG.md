# Changelog

## 0.6.1

- In stack graphs the longest line of branches stays in the leftmost lane, with shorter side branches to its right.
- Stacks in the sidebar draw as a lane graph instead of nesting each layer deeper, so branch names in long stacks stay readable.

## 0.6.0

- The commit message box now has corners that fit inside its card.
- GroveKit, for apps that use it: - `ShellResult` has a public initializer, and `GitRunner`'s defaults are nonisolated, so runners outside GroveKit build without spelling them out. - `DiffParser.parse(_:)` and `DiffParser.fileDiffs(patch:nameStatus:)` are public, as are `DiffResult` and `FileDiff` initializers. - `diff(from:to:)` diffs two revisions. Breaking: it is a new `GitRepositoryProtocol` requirement, so other conformers add it. - `BlameViewModel.open(file:revision:)` blames a file at any ref. - `CommitGraphBuilder.append(_:)` adds a page of commits to the graph without rebuilding it. - Public `ListSelection.init()` and `focus`, `WorkingCopyViewModel.selectedPath`, `PendingHunkDiscard.action` and `RestackPlan.steps`; `PullRequestHost.headRef(number:)`'s default is nonisolated. - `RefName.isValid(_:)` validates ref names and `BranchTreeNode.build(_:)` nests branches into folders. Breaking: `ReflogViewModel.isValidBranchName(_:)` is now `RefName.isValid(_:)`. - `RefActionsViewModel` runs branch, tag, remote, submodule and worktree actions (checkout, rename, delete, merge, rebase, tracking, worktree removal) with undo records, so apps no longer rebuild them. - `GitRepository(path:runner:hosting:naming:)` takes a `GitNaming` for its scratch files, the restack plan's folder and the branch-parent config key; it defaults to `grovekit` names. Pass `GitNaming(name: "grove")` to share restacks and branch parents with Grove. - `ViewModelPreferences.store` and `keyPrefix` (default `grovekit.`) keep the view models' settings apart from an app's own. `HostingError` messages no longer mention Grove or its Settings. - Worktree files, renames and the Trash go through the runner: `WorktreeResolver.mainRepositoryPath(forWorktreeAt:runner:)` and `linkedWorktrees(ofRepositoryAt:runner:)`, `GitRunner.trashItem(at:)` and `watch(_:latency:isRelevant:onChange:)` (both with defaults), and `trashFiles(_:)`. Breaking: `trashFiles(_:)` is a new `GitRepositoryProtocol` requirement, and `moveFile(from:to:)` refuses to overwrite. - `RepositoryWatcher(path:runner:latency:onChange:)` watches a repository through its runner; a linked worktree watches its own git state and the shared refs, ignoring sibling worktrees. - An `onAction: GroveKitActionHandler?` hook on the view models reports each git action they run as a `GroveKitAction`, with whether it succeeded and no user data, for telemetry.
- A window on a worktree now refreshes when its branches change outside Grove, and no longer refreshes for activity in the repository's other worktrees.

## 0.5.1

- Exporting a file from its history now saves the real content of Git LFS files instead of the LFS pointer.

## 0.5.0

- Get a notification when a workflow run finishes: turn on "Notify me when it finishes" when running a workflow, or pick "Notify When Finished" on a running run. Clicking the notification opens the run.
- Run Workflow leaves an input empty when its default is `null` instead of filling in the text "null".
- Click a stack in the sidebar to open it in the Stack tab; the stack on screen stays selected in the sidebar.
- The Stack tab's title now opens a searchable stack switcher, like the repository switcher.

## 0.4.0

- A run's graph now lists the annotations its jobs left, such as errors, deprecation warnings and notices, like GitHub's run summary.
- A run's Artifacts tab in the Actions tab lists the files it uploaded, with size and expiry, and downloads them as zip archives.
- Drag a run's graph to move around it; zooming now scales the graph inside its card instead of growing the card.
- The zoom level resets the graph to actual size when clicked.
- A job opened from the summary has a back button, and Back (⌘[ or the mouse's back button) returns to the summary.
- A run in the Actions tab now opens on a graph of its jobs, wired the way the workflow wires them, with each job's status, including jobs that haven't started yet. Clicking a job in the graph or the list opens its steps and log; Graph at the top of the list goes back, and the graph can be zoomed.
- Selecting a workflow run in the Actions tab shows its jobs and each job's steps, with their status and duration.
- The Actions tab updates by itself while it's open: runs in progress refresh every few seconds, and new runs appear without reloading.
- Job logs in the Actions tab keep their terminal colors, and can be searched: matches are marked, and the arrows or Return step through them, opening the steps they're in.
- Finished jobs in the Actions tab show their log under each step: failed steps open by themselves, groups fold, errors and warnings stand out, and the log can be wrapped and copied.
- Workflow runs can be re-run (all jobs or only the failed ones) and cancelled from the Actions tab.
- Workflows with a manual trigger can be started from Grove: Run Workflow (in the Actions tab, the Git menu and Quick Actions) asks for the branch or tag and the workflow's inputs, then selects the run it started.
- A run's artifacts now sit under its graph and annotations in a Summary, like GitHub's, with each artifact's size and digest, instead of in a separate tab.
- A new Actions tab (Cmd+9) lists the repository’s GitHub Actions workflow runs, filtered by workflow, branch and status; older runs load as the list scrolls.
- Branches in the sidebar show how CI went for their latest commit, and "Show Runs for Branch" opens the Actions tab filtered to them.
- The Actions pill gets a red dot when the checked-out branch's latest run failed.
- A worktree or repository folder deleted outside Grove no longer leaves a broken tab behind: the tab moves to the main repository, or closes when another tab already shows it.
- Grove no longer freezes when a repository suddenly has thousands of changed files, such as a worktree being deleted while it is open.
- With several files selected in Changes, the context menu's Discard Changes, Copy Path, Reveal in Finder and Track with Git LFS now act on every selected file instead of only the one that was right-clicked.
- Pull requests load with a GitHub token that lacks the `read:org` scope; only the names of requested team reviewers are left out.
- Restack a stack in one click from the Stack tab: Restack moves only the branches that drifted from their parent, Sync fetches and moves the whole stack onto the new trunk, and Restack from Here moves one branch and everything on it. Branches checked out in other worktrees are restacked there. A conflict pauses the cascade in Changes, where Continue picks it up and Abort puts every branch back.
- Push Stack pushes every changed branch of a stack at once, and only if nobody else moved them on the remote.
- Stack layers can be checked out, pushed, moved onto another branch, folded into the branch below, or get a new branch on top. Drag a stacked branch onto another branch in the sidebar to move it there with everything on it.
- New pull requests for a stacked branch start out based on the branch it's stacked on.
- When a stacked branch's pull request merges, even as a squash merge, the Stack tab offers to retarget what was built on it. Grove moves those branches onto trunk, pushes them, points their pull requests at trunk on GitHub, GitLab, Bitbucket or Azure DevOps, and offers to delete the merged branch.
- A new Stack tab (⌘9) shows the stack you're on as one tree: each branch's pull request and checks, its own commits and size, whether it's pushed, and which layers need a restack, with trunk at the bottom and splits side by side.
- Stacked branches are recognized on their own, however they were made, and grouped per stack under Branches in the sidebar, with each branch under the one it builds on and a glyph when it needs a restack, its parent merged, or it isn't pushed.

## 0.3.0

- Add a remote to an existing repository from the sidebar, the More menu or Repository Settings. Grove fetches it right away so its branches show up.
- Remove a remote from its context menu in the sidebar or from Repository Settings.
- Branches Review no longer suggests deleting branches that are checked out in a worktree, and labels them "In Worktree".
- Cloning from the remote repository browser now uses the HTTPS URL, signed in with your account's token like Tower, so it works without an SSH key. The SSH URL is still available to copy.
- Copy buttons now highlight when pressed and a "Copied" toast confirms anything copied to the clipboard.
- Right-clicking Grove in the Dock lists your recently opened repositories, plus Clone Repository and New Window.
- Grove's app ID is now `dev.houwert.grove`. After updating, settings start fresh once, and macOS may ask to let Grove use its saved account sign-ins.
- Grove now runs on macOS 15 Sequoia and later. On macOS 15, repositories in the sidebar are dragged one at a time.
- Branches whose pull request was merged now show a merge symbol next to its number, and their name is faded. A branch that has moved on since the merge shows no pull request.
- The push dialog title now says how many commits you're pushing and where to, e.g. "Push 3 commits to main".
- Git errors now explain what went wrong in plain language, like a rejected push or changes that would be overwritten, instead of showing git's raw output.
- Removing a worktree closes the tab showing it when the main repository is open in another tab, and otherwise moves that tab to the main repository.
- Click the repository name at the top of the sidebar, or press ⌥⌘O, to search your repositories and switch to another one on the same tab. The most recently used ones come first, so Return jumps back to the last one.
- The sidebar opens at its full width on every launch instead of getting a little narrower each time.
- Adding a remote makes local branches track their same-named branch on it, like a clone does, so they no longer show as "Not published".
- Track Remote Branch… in a branch's context menu sets or changes the branch it tracks, and Stop Tracking removes it.
- Deleting a branch that another worktree has checked out now explains why git refuses, and offers to remove that worktree first or open it.
- Remove Worktree is now a sheet that can also delete the worktree's branch, or remove it even with uncommitted changes.
- Double-clicking a worktree, or a branch checked out in another worktree, now opens it in a new tab. Switch to Worktree in the context menu still moves the current tab.

## 0.2.0

- Select several commits in History to squash them, or rebase interactively to reorder, reword, squash, fix up or drop commits.
- Switch History between the graph and a compact table, reveal a branch, tag or stash in History, and export commits as a patch or a ZIP.
- Ignore, stop tracking, rename or trash files from the Changes list, save a snapshot of your changes as a stash, and create or apply patches.
- Restore a file to any version from its File History.
- Commit templates in Preferences, a Gitmoji picker, and syntax coloring in diffs.
- Create pull requests and comment on them, on GitHub, GitLab, Bitbucket and Azure DevOps.
- Sign in to your hosting accounts in Preferences > Accounts, or bring them over from Tower or the GitHub and GitLab CLIs.
- Clone in the background with progress, cancel and retry.
- Git LFS, git-flow and git-svn support, plus full submodule actions.
- Commit identities per repository, signing setup with 1Password support, and custom environment variables for git.
- Drag branches in the sidebar to merge, rebase, pull or push.
- A `grove` command line tool that opens a folder in Grove.
