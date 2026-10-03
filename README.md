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

## Requirements

- macOS 14+
- Xcode 16+

## Building

Open `app/Grove/Grove.xcodeproj` in Xcode and build the `Grove` scheme. It pulls in GroveKit from `Packages/GroveKit` as a local package.

## GroveKit

GroveKit is Grove's git engine as a Swift package, for other apps that need a lighter git integration than all of Grove (Argus first). It has the engine (`GitRepository`, `GitShell`, parsers), the git models, and Grove's headless view models (history, working copy, stashes, blame, reflog, branches review, stacks, git-flow, svn) built on Observation. There is no UI in it: no SwiftUI or AppKit, and each app keeps its own views.

Other apps depend on this repository by URL, pinned to a Grove release tag, and `import GroveKit`:

```swift
dependencies: [
    .package(url: "https://github.com/DouweBos/Grove.git", from: "0.6.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "GroveKit", package: "Grove")]),
]
```

The root `Package.swift` exposes the product; the sources live in `Packages/GroveKit`. Build and test it with `swift build && swift test` from the repository root.

Git runs through a pluggable `GitRunner`: it runs git invocations and reads and writes files in the worktree. `LocalGitRunner` runs the `git` on this Mac today; a remote runner (for example over a host gateway) can implement the same protocol without changing callers. Open a repository with `GitRepository(path:runner:hosting:)`; pull requests and CI come from a `RepositoryHosting` the app provides, and without one they behave as for a repository without a hosted remote.

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
