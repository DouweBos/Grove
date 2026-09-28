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

## In progress

- Undo/redo: menu commands still replace text undo, so Cmd+Z in text fields is broken; only reflog and branch-review actions record undo; undo errors are never shown. Quick Open and Navigate > Blame/Settings are unwired.
- Remote: pull can't force `--no-rebase`; push can't set upstream on first push; comparison shows one direction; branch review can force-delete when the merged check fails.
- Diffs: the warn-before-hunk-discard preference is ignored; line wrapping differs between views; the diff panel is too narrow at 900pt; image diffs and external diff/merge tools are unwired; history arrow keys need a click first; dead components remain.

## Known limits

- Bookmarks imported by the old Tower importer carry future last-opened dates; they're hidden in the UI, and re-importing restores real ones.
- New protocol methods have no-op defaults for test doubles, so a missing `GitRepository` implementation fails silently.
