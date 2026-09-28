# Grove

A macOS Git client built with SwiftUI. Its design language follows our disk analyzer Charon (`../Charon`).

## Development Guidelines

- This is not a production app. Never plan or implement data migrations — just refactor directly.
- Prefer functions on ViewModels over writing to properties directly. This makes adding analytics easier later.
- ViewModels use `@Observable` and `@MainActor`. `RepositorySession` owns every per-repository ViewModel; call `refreshAll()` after a git mutation instead of refreshing individual lists.
- Never move toolbar items out of `.toolbar {}` into the view hierarchy.

## Design system

1. All colors come from `Theme` (asset catalog tokens, light and dark). No `Color.red`, `Color(red:)`, hex, or `Color(nsColor:)` in views.
2. Content sits in cards (`.card()`, or `.panel()` for edge-to-edge lists) on `Theme.background`.
3. SF Symbols only, no emoji. Hashes, paths, counts and dates use `.monoCaption`.
4. Reusable components live in `DesignSystem/`, each with a `#Preview`. Check there before building a one-off.
5. Top-level navigation is the pill bar in the toolbar (`RepositoryTab`); the sidebar holds refs only.

## Build and test

```sh
cd app/Grove
xcodebuild -project Grove.xcodeproj -scheme Grove -derivedDataPath build -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Grove.xcodeproj -scheme Grove -derivedDataPath build -destination 'platform=macOS,arch=arm64' test -only-testing:GroveTests
```

Dev launch flags: `-GroveOpenRepository <path>` opens a repository on launch, `-GroveAction <GroveAction rawValue>` (e.g. `navigateHistory`) runs an action once it's open, `-GroveAppearance dark|light` forces an appearance, `-GroveSidebar hidden` collapses the sidebar. Without `-GroveOpenRepository`, `-GroveAction showRemoteRepositories` opens the cloud browser.

Never perform git writes against real repositories while testing; use a scratch repo under `/tmp`.

Releases: run the Release workflow on `main` with a `beta` or `production` channel. It runs `fastlane mac release`, which takes the version from the pending changesets, signs, notarizes and appends to the Sparkle appcast served through houwert.dev/grove/updates.

## Conventions

- Files under 500 lines, views under 300; split when approaching that.
- Commit when a thing is done. Every feature, fix or refactor gets its own commit the moment it works — don't leave finished work sitting in the tree waiting for the end of the session. One commit per feature/fix, with its tests and docs in it, so each one stands alone and is revertable. Several unrelated changes already piled up in the tree → split them by hunk rather than committing one lump. Committing is not pushing: push only when asked.
- Commit messages: Conventional Commits, `type(scope): subject`, one short lowercase subject.
- Comments explain why, in 1–2 lines, describing the code as it stands.
- User-facing changes add a changeset: `.changeset/<name>.md` with front matter `"grove": minor` (new features) or `"grove": patch` (fixes), and a short note for users (a `- ` list for several). These become the release notes and set the version bump. Never write `major`: Grove stays 0.x until 1.0 is a deliberate decision, and the release lane rejects it.
