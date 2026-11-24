# Changelog

## 0.11.0

- Cancelling a clone the moment it starts stops it, also when the Mac is busy.
- Error and warning banners can be dismissed and stay dismissed when the repository refreshes, and Blame and CI artifacts offer their Retry buttons again.
- "Open Blame at This Revision" in File History opens Blame at that commit, also from before the file was renamed.
- GroveKit, for apps that use it: additions only. `HistoryViewModel.fileHistory(path:)` with `onOpenBlame`, and ways to dismiss the Blame, File History, merge status and Git LFS banners. A dismissed refresh error stays dismissed until a read works or fails differently.
- Unstaging or discarding selected lines changes exactly those lines.
- Hunk and line actions keep a missing newline at the end of a file, and work with renamed, added and deleted files and with paths that have spaces or other scripts.
- An action on a diff that is out of date is refused instead of changing other content.
- GroveKit, for apps that use it: no API changes. Hunk actions take hunks and lines as `diff(for:staged:ignoreWhitespace:)` returned them, paths from status and diffs come unquoted, and a staged rename's diff has its `oldPath`.
- Grove no longer quits when git stops reading a long list it was given.
- Diffs stay fast at 100,000 lines, also with Wrap Lines, and can be shown side by side. Added, deleted, renamed and untracked files can be staged, unstaged and discarded by hunk and line. Click a line to select it, Shift- or Command-click for more; drag along a line to copy part of it.
- GroveUIKit, for apps that use GroveKit: a new product with Grove's git UI, starting with its style, feature checks and primitives. GroveKit adds `GitCommandPerforming`, push tag options, squash merge, stash keep-index and branch, and remote rename and prune. The refs, reflog, branches review and stash view models run their changes, and their undo, through their `commands`, which an app can set.
- GroveKit: `FileStatus.supportsHunkActions` says which changes can be staged by hunk and line, and the diff's models can be used off the main actor.
- GroveUIKit adds the diff: `GitDiffPane` and `GitDiffView` with unified and split layouts, word and syntax highlights, Wrap Lines, image and Git LFS diffs, hunk and line actions, and slots for an app's own rows and controls. An app's copy, toast and open-file come in through `GitUIHost`.
- GroveKit's `GitCommand` adds pushing a branch that isn't checked out (`pushBranch`), `sync`, `renameCurrentBranch`, and checking out after stashing or discarding changes; `.fetch(remote: nil)` fetches every remote, and a snapshot with nothing to save throws `GitCommandError.nothingToSnapshot`. `GitFeature` adds `verifySignatures` and `recurseSubmodules`, which pulls and pushes with those options need. Apps that switch over either enum need the new cases.
- GroveUIKit adds the dialogs: fetch, pull, push, sync, new, rename, delete and track branch, merge, rebase, stash, snapshot, tag, add or edit a remote, and a branch from a stash, as `GitDialogView`, shown from anywhere through `GitDialogPresenter`. Each submits a public `Git…Form` through the app's `GitCommandPerforming`, offers only what its `GitFeatures` allow and says why the rest is off. Their template (`GitDialogSheet`, `GitDialogCard`, `GitDialogField`, `GitDialogOptionRow`, `GitDialogOptionsSection`, `GitDialogPathField`, `GitComboBox`) is public for an app's own sheets.
- GroveKit: `GitCommand.saveConflictResolution` and `WorkingCopyViewModel.saveConflictResolution(_:contents:)` resolve a conflict with an edited result through the view model's `commands`, and `commitBlocker` says why Commit is off. `GitRepositoryProtocol` adds `saveConflictResolution(path:contents:)`; apps that switch over `GitCommand` need the new case.
- GroveUIKit adds the working copy: `GitWorkingCopyView` with the composer, file list, patches, the operation banner and a conflict resolver that edits the merged result, and `GitConflictsView` for the conflicts alone. An app brings its own parts through `GitWorkingCopyHost` (open file, identity profiles, templates, dialogs, diff and merge tools, patch panels, focus and events) and `GitWorkingCopySlots` (header, row, row menu, composer, diff, or a replacement for the files and diff); `gitWorkingCopyDialogs` shows the discard, rename and Trash confirmations wherever its files are listed, and `GitAvatar` draws an initial.
- GroveUIKit: `GitWorkingCopyView` takes a `GitWorkingCopyLayout`; below its two columns' width, or always with `.compact(composer:)`, it shows the file list over the diff, with or without the composer. The file list has a filter, and All Files rows have menus. `GitWorkingCopyHost` adds `compactDiffHeight` and `presentsDialogs`, `GitWorkingCopySlots` adds `filesDetail` and `trackedFileMenu`.
- GroveKit's `GitCommand` adds the history rewrites: `cherryPick`, `revert`, `reset(to:mode:)`, `reword`, `squash`, `drop` and `rebaseInteractive(onto:steps:)`; `HistoryViewModel` runs all its changes, checkout included, through its new `commands`, and a cherry-pick, revert or rebase that stops on a conflict calls `onRebaseStopped`. `selectAll()` selects every listed commit. `GitRepositoryProtocol.mergePreview(base:compare:)` reads where two refs meet and whether merging would conflict. `RebaseStep` and `RebaseAction` are nonisolated. Apps that switch over `GitCommand` need the new cases.
- GroveUIKit adds History: `GitHistoryView`, whose commit list is an AppKit table that stays fast at 100,000 commits, with the commit's detail, changeset and tree, a multi-selection summary and every commit action's sheet; `GitCompareView`, `GitFileHistoryView` and `GitInteractiveRebaseView` on their own; and `GitCommitRow`. An app brings its title, dimmed commits, compare, rebase, blame, avatars, diff options and review rows through `GitHistoryHost`. Tests and drivers find the list as `GitCommitTableView`.
- GroveKit's `BlameViewModel` lays out a blamed file off the main thread, keeps `commitCount` instead of counting on every read, and adds `close()` to go back to picking a file. `BlameLine` is `Sendable`.
- GroveUIKit adds Blame: `GitBlameView`, the file picker beside the blamed file, whose lines are an AppKit table that stays fast at 100,000 lines, with each run's commit, author, date and age. An app brings routing of picked files, Show Commit in History and file icons through `GitBlameHost`, and opens a line through `GitUIHost.openFile`. Tests and drivers find the table as `GitBlameTableView`. `GitSelectableList` and `gitSelectableRow(isSelected:)` are public for an app's own lists.
- GroveKit's `GitCommand` adds `fastForward(branch:remote:remoteBranch:)` and the submodule commands `initSubmodule`, `updateSubmodule`, `fetchSubmodule` and `removeSubmodule`, which need `GitFeature.submodules`. `RefActionsViewModel` runs submodules and cherry-picks through its `commands`, and `checkout(named:carrying:)` can stash or discard what would block a checkout. Apps that switch over `GitCommand` need the new cases.
- GroveUIKit adds the refs sidebar, `GitRefsSidebar` with `GitRefsModel`: branches in folders with pinned and protected ones first, worktrees, archived branches (also gone ones), remotes, tags and submodules, a filter, Show More for long lists, drag and drop to merge, rebase, pull and push, and asking to stash or discard when changes block a checkout. An app brings its marks, worktree, submodule, pull request, history, export and compare actions, its own rows and drops through `GitRefsHost`, its rows' branch actions through `gitRefBranchRow(_:)`. Also `GitStashesView`, `GitReflogView`, `GitBranchesReviewView`, `GitChangesetBrowser`, `GitSidebarRow`, `GitAheadBehind` and `GitFolderExpansion`.
- History sorts and groups commits by commit date, so rebased commits no longer break up the day headers.
- History keeps the selected commit's date in view when it first opens.
- Repositories with thousands of branches open again instead of crashing while stacks are read.
- Pull can take a remote branch that isn't in the list: choose Other Branch and type it.
- Blame stays fast with very long files and shows each change's author, with newer changes tinted more strongly.
- Click a change's commit to see the file before it, Option-click a line to open it in your editor, and right-click for Show Commit in History, Copy SHA or Copy Line. Select lines and press Command-C to copy them.
- In a narrow window Blame shows the file list and the file one at a time.
- Push can send annotated tags on the pushed commits, or all tags.
- Merge can squash the branch into one commit to make, Stash can keep staged changes in the working copy, and New Tag can tag any branch, tag or commit.
- Delete Branch warns when the branch has commits the checked-out branch doesn't, and ticks Delete Even if Unmerged for it. Track Remote Branch also takes a name typed in.
- A branch created without checking it out can be undone.
- History stays fast with very long histories. Return or a double-click checks out the selected commit after asking, Command-A selects every commit, Command-C copies the selected SHAs, and Page Up, Page Down, Home and End move through the list.
- Several selected commits can be squashed, saved as a patch or have their SHAs copied from the detail pane.
- Compare takes branches, tags and commits, shows where they meet and whether merging would conflict, and opens each changed file into its diff.
- A cherry-pick or revert that stops on a conflict takes you to Changes to resolve it.
- The sidebar has a filter at the bottom, and long lists like tags show their first rows with Show More, so repositories with thousands of branches and tags stay fast.
- Branch menus add Squash-Merge, Push or Publish, Pull, and Check Out works for tags; remotes add Fetch, Prune Stale Branches and Rename or Set URL; tags add Push. Archived branches that no longer exist stay listed so they can be unarchived.
- When uncommitted changes block a checkout, Grove offers to stash them and bring them along or to discard them.
- The reflog lists the selected entry's changed files, and New Branch at an entry uses the same dialog as everywhere else. Stashes add New Branch from Stash and Copy Message.
- Menu items no longer end in an ellipsis.
- Conflicts are resolved in the Changes tab with both versions above the merged result, which can be edited and saved as the resolution. Binary conflicts say so instead of showing their bytes.
- Return or a double-click opens a changed file, and the Files menu also has Stage All and Unstage All.
- The commit identity menu can save the identity as a profile or remove one.
- In a narrow window, Changes shows the file list over the diff, split by a gap you can drag, under the commit message.
- The file list has a filter, and files in All Files have a menu to open, copy or reveal them.
- Stash files straight from the Changes context menu: "Stash N Files" opens the Stash dialog with the selection ticked.

## 0.10.0

- Pull and fetch try again on their own when another app fetched the same remote at the same moment, instead of failing with "cannot lock ref".
- Git errors no longer list every updated remote branch.
- Pulling in a Git LFS repository skips the extra LFS download when the checkout already fetched every file.
- Fetch, Pull, Push and Sync show git's progress as a bar.
- Cancel in those dialogs now stops git instead of leaving it running in the background.
- Press Cmd-A in the Changes file list to select every changed file.
- Fetch, pull and push give up with an error when the remote stops responding, instead of hanging.

## 0.9.0

- Checking out a branch from the sidebar shows progress while git works.
- Deleting a local branch no longer asks to force it when a remote already has all its commits.
- Drag across files in Changes to select them.
- Check out any commit from its context menu in History, e.g. a remote tip after a force push.
- Reset HEAD to a commit also works while History shows the checked-out branch.
- The Pull dialog fits long branch names instead of spilling out of the sheet.
- The sidebar status badges wrap onto a new line instead of truncating.

## 0.8.1

- Folders under a remote open again.
- Running actions count up their running time in the runs list.

## 0.8.0

- Double-click a remote branch to check it out locally.
- Remote branches are grouped into "prefix/" folders, like local branches.
- Sidebar sheets and confirmations open right away and close on the first Cancel, instead of lagging and reopening in a loop.
- The main branch is listed first in Branches and under each remote.

## 0.7.1

- Pull, Sync and dropping a remote branch on the checked-out one open on your configured pull strategy instead of showing Merge and then switching.

## 0.7.0

- A stack whose bottom branch gained new commits keeps that branch at the bottom instead of sometimes flipping it above the layers built on it.
- The sidebar waits for stacks before listing branches, so a stacked branch never shows up loose in its folder first.
- The `grove` command does more from Terminal, for you and for scripts and agents handing work over to Grove: - `grove history [branch]`, `grove blame <file>` and `grove stack [branch]` open Grove right on that view - `grove stacks`, `grove branches` and `grove prs` print the repository's stacks, branches and open pull requests, with `--json` for scripts - `grove -C <path>` runs it for another folder, and `grove help` lists everything
- The `grove` command is now installed as a link to Grove, so it stays up to date with the app
- Installing it no longer replaces a `grove` command from another program, and asks before replacing a link you made yourself
- Settings > Advanced shows the command line tool, and updates an older copy or repairs one that broke when Grove was moved or renamed
- A branch folder no longer stays open after the checked-out branch moves into a stack
- Stacks in the sidebar start collapsed unless they hold the checked-out branch

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
