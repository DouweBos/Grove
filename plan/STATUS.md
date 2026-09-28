# Status

Where the overhaul stands. Update this when a wave of work lands.

## Done (merged to main)

- Charon design system: Theme tokens (light and dark), cards/panels, pill tabs in the toolbar, badges, banners.
- Changes: Staged/Changes/Conflicts sections, real git identity, amend and sign-off, discard with confirmation, untracked diffs, conflict banner and resolver.
- History: lane graph, commit detail, Revert/Reset/Reword/Squash/Delete, tree tab, file history, compare with HEAD, filter and paging.
- Browser and sidebar: File menu, groups, filter, Open button, last-opened fix, archived branches, ahead/behind fix.
- Dialogs: shared layout, inline errors and progress, session-wide refresh on completion.
- Stashes (confirmed apply/pop/drop, shared diff), Reflog (confirmed reset, create branch), Pull Requests (real `gh` data, typed empty/error states), Blame (all tracked files), Quick Actions palette.
- Settings: fake tabs removed; Repository Settings on `git config --local`; Git Config tab reads global config, writes on Save; Accounts shows `gh auth status`; auto-fetch interval is live.
- `GitRepository` and `MockData` split into themed files; swiftlint clean.

## Done in wave 2

- Undo/redo: text undo works in text fields; commit, amend, stage/unstage, checkout, branch delete and history rewrites are undoable; grouped multi-branch delete; failures show an alert. Quick Open and Navigate > Blame/Settings (Cmd+7/8) wired.
- Remote: explicit pull strategy (merge/rebase/ff-only) overrides config; first push sets upstream; sync on new branches; force push is lease-only and confirmed; two-sided branch comparison; branch review blocks deletes when the merged check fails.
- Diffs: hunk-discard confirmation with "don't ask again"; one no-wrap diff everywhere with pinned gutter and a remembered Wrap Lines toggle; image diffs; open in diff/merge tool; Changes stacks below ~650pt; history arrow keys; dead components removed.
- Toolbar fits at the 900pt minimum: unselected pills collapse to icons when narrow, sidebar capped at 300pt. Unpublished branches show "Not published".

- Worktrees: browser nests linked worktrees under their main repository (Tower import folds them); in-repo sidebar lists worktrees and submodules with state. A window runs git in one worktree at a time: the header switcher, a double-clicked worktree, or a double-clicked branch checked out elsewhere switches it (tab kept); other branches check out on double-click.

- Home buttons: cloud and disk in the sidebar (top bar when collapsed) leave the repository; the cloud browses GitHub repositories of the `gh` account and its organizations (clone, or open the local clone), the disk lists local ones. File menu: Local/Remote Repositories (Shift-Cmd-L / Shift-Cmd-K).

- Windows and tabs: any number (File > New Tab ⌘T, the tab bar +, New Window ⌥⌘N, Open in New Tab / Window on a repository); menu commands and mouse navigation go to the key window; two windows on one repository share its fetches. Deleting a repository asks Keep Files or Move to Trash.

- Background fetch: closing the window keeps Grove running; cached repositories keep auto-fetching (every 5 minutes by default) and the reopened window resumes where it was. History logs the branch with its upstream, marking unpulled and unpushed commits.

- Distribution: Sparkle updates (stable and beta channels, Check for Updates menu, beta toggle in Preferences); release workflow reuses Argus's match cert and notarization key; see tools/release/README.md.

- Back / forward: window history across the browsers, repositories and their tabs; toolbar arrows, Cmd-[ / Cmd-], and mouse buttons 4/5.

- Performance: per-session shared ref cache and paused session reuse (LRU 4); per-item detail caches; Branches Review via for-each-ref; git runs off the main actor with concurrent pipe draining (ProcessRunner), ~85% faster across the board. Fixture generator + opt-in benchmarks in tools/fixtures (bench.sh, baseline.json).

## Open

- Branches Review's merged-check error state and grouped-delete undo are unit-tested but not seen in the UI.
- Image previews: stash untracked files show one side missing; PR changesets have none.
- Undo in Preferences text fields is untested (typing there writes real settings).

## Known limits

- Bookmarks imported by the old Tower importer carry future last-opened dates; they're hidden in the UI, and re-importing restores real ones.
- New protocol methods have no-op defaults for test doubles, so a missing `GitRepository` implementation fails silently.
