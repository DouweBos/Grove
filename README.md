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

Open `app/Grove/Grove.xcodeproj` in Xcode and build the `Grove` scheme.

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
│   ├── FileWatcher             # FSEvents wrapper for live refresh
│   ├── GitUndoManager          # Reversible git operation stack
│   └── RepositoryManagerProtocol
├── GitKit/          # Git CLI wrapper and protocol
│   ├── GitRepository           # Concrete async git CLI wrapper
│   ├── GitShell                # Process spawning layer
│   ├── GitRepositoryProtocol   # Central contract for all git operations
│   └── Parsers/                # Output parsers (diff, reflog, PR, etc.)
├── Models/          # Domain value types
│   ├── GitTypes     # CommitInfo, BranchInfo, TagInfo, RemoteInfo, etc.
│   ├── DiffTypes    # DiffResult, HunkData, DiffLine, FileDiff
│   ├── StatusTypes  # StatusEntry, FileStatus
│   ├── PRTypes      # PullRequestInfo, PRState, PRLabel, PRComment
│   ├── StashTypes, BlameTypes, ReflogTypes, CloneTypes
│   └── BookmarksStore  # Bookmark/group data + plist container
├── Mocks/           # MockGitRepository for previews and testing
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

- **Protocol-driven**: Views and ViewModels depend on `GitRepositoryProtocol`, never on the concrete `GitRepository`. This enables `MockGitRepository` for previews and tests.
- **Observable ViewModels**: All ViewModels are `@MainActor @Observable` classes, injected into the view hierarchy via `.environment()`.
- **RepositorySession**: A single `@Observable` object per repository window that owns all ViewModels, the file watcher, auto-fetcher, and undo manager. Keeps the view layer thin.
- **Notification commands**: Menu bar shortcuts post `GroveAction` notifications, handled centrally by `RepositorySession.handleAction(_:)`.
- **Plist persistence**: Bookmarks and groups are serialized to `~/Library/Application Support/Grove/bookmarks.plist` via `PlistStore`. Preferences use `@AppStorage` (UserDefaults).

### Data Flow

```
Git CLI  →  GitShell  →  Parsers  →  Domain Types  →  ViewModels  →  Views
              ↑                          (Models/)       (@Observable)  (SwiftUI)
         GitRepository
     (GitRepositoryProtocol)
```

1. `GitRepository` invokes git commands through `GitShell` (async `Process` wrapper).
2. Raw output is parsed into domain types (`CommitInfo`, `DiffResult`, etc.) by dedicated parsers.
3. ViewModels hold parsed data and expose it as `@Observable` state.
4. SwiftUI views bind to ViewModel properties and trigger actions back through the protocol.
