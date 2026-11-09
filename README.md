# Grove

A native macOS Git client built with SwiftUI.

## Features

- Repository browser with drag-and-drop support
- Commit history with diff viewing
- Working copy management (stage, unstage, commit)
- Branch, tag, and remote management
- Stash support
- GitHub Actions: workflow runs, jobs, logs and artifacts; run, re-run and cancel workflows
- Git blame viewer
- Merge conflict resolution wizard
- Quick actions command palette
- Import repositories from Tower

## Download

Signed, notarized builds with automatic updates are at [houwert.dev/grove](https://houwert.dev/grove).

## Requirements

- macOS 15+
- Xcode 26+ to build (Swift tools 6.2)
- `git` on your `PATH`

## Building from source

```sh
git clone https://github.com/DouweBos/Grove.git && cd Grove
swift build && swift test   # GroveKit
cd app/Grove
xcodebuild -project Grove.xcodeproj -scheme Grove -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
open build/Build/Products/Debug/Grove.app
```

Or open `app/Grove/Grove.xcodeproj` in Xcode, pick your own team under Signing & Capabilities, and run the `Grove` scheme. It pulls in GroveKit from `Packages/GroveKit` as a local package; the only remote dependency is [Sparkle](https://github.com/sparkle-project/Sparkle).

Grove uses no private Apple frameworks and needs no paid Apple Developer account to build and run locally: a free Apple ID or ad-hoc signing (as above) is enough. A paid account is only needed to sign with a Developer ID and notarize for distribution, which the maintainer's release workflow does. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## GroveKit

GroveKit is Grove's git engine as a Swift package, for other apps that need a lighter git integration than all of Grove (Argus first). It has the engine (`GitRepository`, `GitShell`, parsers), the git models, and Grove's headless view models (history, working copy, stashes, blame, reflog, branches review, stacks, git-flow, svn) built on Observation. There is no UI in it: no SwiftUI or AppKit, and each app keeps its own views.

GroveKit has no dependencies of its own, so it resolves as a plain public SwiftPM package. Other apps depend on this repository by URL, pinned to a Grove release tag, and `import GroveKit`:

```swift
dependencies: [
    .package(url: "https://github.com/DouweBos/Grove.git", from: "0.5.1"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "GroveKit", package: "Grove")]),
]
```

The root `Package.swift` exposes the product; the sources live in `Packages/GroveKit`. Build and test it with `swift build && swift test` from the repository root.

Git runs through a pluggable `GitRunner`: it runs git invocations, reads and writes files in the worktree, moves them to the Trash and watches folders. `LocalGitRunner` runs the `git` on this Mac today; a remote runner (for example over a host gateway) can implement the same protocol, building results with `ShellResult(stdout:stderr:exitCode:stdoutData:)`, without changing callers. Trash and watching have defaults that report "unsupported", so a runner only adds them when its machine can. Open a repository with `GitRepository(path:runner:hosting:naming:)`; pull requests and CI come from a `RepositoryHosting` the app provides, and without one they behave as for a repository without a hosted remote.

What GroveKit writes carries the app's names: `GitNaming` sets the scratch-file prefix, the folder in the git directory that holds a running restack, and the branch-parent config key (`grovekit` by default; Grove passes `grove`, and apps that pass the same see each other's restacks and branch parents). The view models' settings live in `ViewModelPreferences.store` under `keyPrefix`.

Besides the per-tab view models, apps get `RefActionsViewModel` (checkout, rename, delete, merge, rebase, remotes, tracking, submodules and worktrees, with undo records), `RepositoryWatcher` (refreshes on outside changes through the runner; a linked worktree ignores its siblings), `BranchTreeNode` and `RefName` for ref lists, and `DiffParser` for patches from elsewhere. Every view model takes an `onAction` hook that reports each git action as a `GroveKitAction` and whether it succeeded, with no user data, for telemetry.

## Architecture

### Directory Structure

```
Grove/
├── Commands/        # Menu bar actions dispatched via NotificationCenter
├── Components/      # Reusable UI components (avatars, diff stats, etc.)
├── Domain/          # Business logic, services, and protocols
│   ├── RepositorySession       # Per-window ViewModel bundle & lifecycle
│   ├── RepositoryManager       # Bookmark persistence (plist-backed)
│   ├── AutoFetchScheduler      # Periodic background fetch
│   ├── Hosting/                # Accounts, pull request and CI hosts
│   └── RepositoryManagerProtocol
├── Git/             # How Grove runs GroveKit: runner environment, hosting, signing
├── Models/          # App-only value types (bookmarks, clones, sidebar items)
├── Mocks/           # MockRepositoryManager for previews and testing
├── Views/
│   ├── History/     # Commit list, detail, branch comparison
│   ├── WorkingCopy/ # Staging area, diff viewer
│   ├── PullRequests/# PR list and detail
│   ├── CI/          # Actions tab: workflow runs, jobs, logs, artifacts
│   ├── Sidebar/     # In-repository navigation sidebar
│   ├── Toolbar/     # Repository toolbar and status bar
│   ├── Settings/    # Preferences window tabs (@AppStorage-backed)
│   ├── Repositories/# Repository browser and window shell
│   └── Root/        # Tab bar and window host
└── Utilities/       # Logging, helpers
```

### Key Patterns

- **GroveKit**: the engine, git models and headless ViewModels live in `Packages/GroveKit` (see above); the folders here hold the views and Grove-only domain.
- **Protocol-driven**: Views and ViewModels depend on `GitRepositoryProtocol`, never on the concrete `GitRepository`. This enables `MockGitRepository` for previews and tests.
- **Observable ViewModels**: All ViewModels are `@MainActor @Observable` classes, injected into the view hierarchy via `.environment()`.
- **RepositorySession**: A single `@Observable` object per repository window that owns all ViewModels, the file watcher, auto-fetcher, and undo manager. Keeps the view layer thin.
- **Notification commands**: Menu bar shortcuts post `GroveAction` notifications, handled centrally by `RepositorySession.handleAction(_:)`.
- **Plist persistence**: Bookmarks and groups are serialized to `~/Library/Application Support/Grove/bookmarks.plist` via `PlistStore`. Preferences use `@AppStorage` (UserDefaults).

### Data Flow

```
Git CLI  →  GitRunner  →  GitShell  →  Parsers  →  Domain Types  →  ViewModels  →  Views
              ↑                          (Models/)       (@Observable)  (SwiftUI)
         GitRepository
     (GitRepositoryProtocol)
```

1. `GitRepository` invokes git commands through `GitShell`, which hands them to a `GitRunner` (`LocalGitRunner` spawns `git`).
2. Raw output is parsed into domain types (`CommitInfo`, `DiffResult`, etc.) by dedicated parsers.
3. ViewModels hold parsed data and expose it as `@Observable` state.
4. SwiftUI views bind to ViewModel properties and trigger actions back through the protocol.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, test and sign Grove yourself, and for the commit conventions. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md), and report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

Grove is released under the [MIT License](LICENSE). Copyright (c) 2026 Douwe Bos.
