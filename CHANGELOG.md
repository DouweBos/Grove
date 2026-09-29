# Changelog

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
