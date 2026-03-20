# Grove — Development Conventions

This document defines the patterns, naming rules, and constraints that all
workstream agents must follow. Deviating from these conventions will create
merge conflicts and architectural drift.

---

## 1. Protocol-First Development

Every feature starts with the protocol, not the concrete type.

- View code and ViewModels **always** reference protocol types (`any GitRepositoryProtocol`,
  `any RepositoryManagerProtocol`), never concrete implementations.
- Protocols live in `Protocols/` and are **frozen after Phase A** (WS0).
  Additive changes (new methods) require coordination between workstreams.
- Concrete implementations (`GitKit.Repository`, real `RepositoryManager`) live
  in `Domain/` or the `Packages/GitKit/` local package.

```swift
// Correct — depends on protocol
final class WorkingCopyViewModel {
    let repository: any GitRepositoryProtocol
}

// Wrong — depends on concrete type
final class WorkingCopyViewModel {
    let repository: GitKitRepository
}
```

---

## 2. Observable ViewModels

All ViewModels use the `@Observable` macro (Swift 5.9 Observation framework).
Do **not** use `ObservableObject` / `@Published`.

```swift
import Observation

@Observable
final class WorkingCopyViewModel {
    var status: [StatusEntry] = []
    var isLoading = false
    var errorMessage: String?

    let repository: any GitRepositoryProtocol

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.refreshStatus()
            status = try await repository.status()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

Inject ViewModels into views via the `.environment` modifier or direct
initialiser injection. Use `@Environment(ViewModel.self)` at consumption
sites — not `@StateObject` or `@EnvironmentObject`.

---

## 3. MainActor Isolation

- All ViewModels and protocol implementations are `@MainActor`.
- The `GitRepositoryProtocol` is declared `@MainActor`. Implementations must
  forward libgit2 work onto a background `RepositoryActor` (or equivalent)
  and return to the main actor before mutating observable state.
- Never `DispatchQueue.main.async` — use `await MainActor.run { }` when
  returning from a background actor.

```swift
// In a @MainActor ViewModel:
func commit(message: String) async throws {
    // Protocol method is @MainActor, so this is safe.
    let info = try await repository.commit(message: message, body: nil, amend: false)
    recentCommit = info
}
```

---

## 4. Async / Await Everywhere

- Use `async throws` for all operations that touch I/O or Git state.
- Never block the main thread. No synchronous Git calls on main.
- Use structured concurrency (`async let`, `TaskGroup`) for parallelism inside
  a single view refresh cycle.
- Support `Task.isCancelled` in long operations where possible.

---

## 5. Value Types for Data

All model types exchanged across protocol boundaries are value types (`struct`
or `enum`) and conform to `Sendable`. This makes them safe to cross actor
boundaries without copies being shared.

- `CommitInfo`, `BranchInfo`, `StatusEntry`, etc. — all `struct`, `Sendable`.
- Never expose mutable reference types from protocol methods.

---

## 6. Error Handling

Define domain-specific error types that conform to `LocalizedError`:

```swift
enum GroveError: LocalizedError {
    case repositoryNotFound(path: String)
    case stagingFailed(path: String, underlying: Error)
    case mergeConflict(files: [String])

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let path):
            return "No Git repository found at \(path)."
        case .stagingFailed(let path, _):
            return "Could not stage \(path)."
        case .mergeConflict(let files):
            return "Merge conflict in \(files.joined(separator: ", "))."
        }
    }
}
```

Propagate errors upwards to ViewModels. ViewModels catch and expose
`errorMessage: String?` for the UI.

---

## 7. SwiftUI Patterns

### View Structure

Keep views thin. Business logic belongs in ViewModels.

```swift
struct WorkingCopyView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel

    var body: some View {
        // Layout and bindings only — no Git logic here.
    }
}
```

### Previews

All previews inject `MockGitRepository` or `MockRepositoryManager`:

```swift
#Preview {
    WorkingCopyView()
        .environment(WorkingCopyViewModel(repository: MockGitRepository()))
}
```

### State Ownership

| State type | Owned by |
|---|---|
| Transient UI state (selection, expansion) | `@State` in the view |
| Shared domain state | ViewModel (`@Observable`) |
| Cross-window data | `AppState` singleton via `.environment` |
| Persisted preferences | SwiftData via `@Query` / `@Environment(\.modelContext)` |

---

## 8. Naming Conventions

| Category | Convention | Example |
|---|---|---|
| Protocols | `*Protocol` suffix | `GitRepositoryProtocol` |
| ViewModels | `*ViewModel` suffix | `WorkingCopyViewModel` |
| Views | Descriptive noun phrase | `CommitComposerView` |
| Mocks | `Mock*` prefix | `MockGitRepository` |
| Value types | Plain noun | `CommitInfo`, `BranchInfo` |
| Actions / commands | Verb phrase | `StashCreateCommand` |
| Errors | Plain enum | `GroveError` |

File names match the primary type they declare (one type per file for
protocols and ViewModels; views may group closely related small views).

---

## 9. Directory Ownership (Phase B)

Do not create or modify files outside your owned directories.

| Directory | Owner |
|---|---|
| `Protocols/` | WS0 (frozen) |
| `Models/` | WS0 (frozen — additive extensions only) |
| `Mocks/` | WS0 (frozen — additive mock data only) |
| `Packages/GitKit/` | WS1 |
| `Views/Repositories/` | WS2 |
| `Views/Toolbar/` | WS2 |
| `Views/Settings/` | WS2 (structure) → WS7 (panels) |
| `Domain/` | WS2 (Manager/Watcher) + WS5 (AppState/wiring) |
| `Views/WorkingCopy/` | WS3 |
| `Views/Diff/` | WS3 |
| `Components/DiffViewer/` | WS3 |
| `Views/History/` | WS4 |
| `Views/Sidebar/` | WS4 |
| `Components/CommitGraph/` | WS4 |
| `Views/Merge/` | WS6 |
| `Views/Stashes/` | WS6 |
| `Views/Blame/` | WS7 |
| `Views/QuickActions/` | WS7 |
| `Commands/` | WS7 |
| `Resources/` | WS7 |

---

## 10. Xcode Project — Folder References

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16
folder references). Any `.swift` file added inside `app/Grove/Grove/` is
automatically compiled without touching `project.pbxproj`.

This is the primary mechanism for keeping parallel branches merge-conflict-free.
Never revert to explicit file references.

---

## 11. Keyboard Shortcuts and Menu Commands

All menu bar commands and keyboard shortcut registrations are owned exclusively
by WS7 (`Commands/`). Other workstreams must not add `Commands {}` blocks to
the app scenes or register `.keyboardShortcut` modifiers on toolbar buttons that
are intended to become global shortcuts.

Button-level shortcuts internal to a view (e.g. Return to commit, Escape to
cancel) are exempt and can be added by the owning workstream.

---

## 12. Drag-and-Drop

Use SwiftUI's `draggable()` / `dropDestination()` and `Transferable` protocol.
Detect the Option key modifier via `NSEvent.modifierFlags` inside drop handlers
for alternate actions (e.g. Rebase instead of Merge when dropping a branch).

---

## 13. Testing

- Unit tests live in `GroveTests/`.
- Use `MockGitRepository` for all ViewModel unit tests.
- Async test methods use `async throws` and `XCTest.fulfillment(of:)`.
- UI tests live in `GroveUITests/`.
- Target: >80% coverage on ViewModel logic.

```swift
final class WorkingCopyViewModelTests: XCTestCase {
    func testRefreshPopulatesStatus() async throws {
        let mock = MockGitRepository()
        let viewModel = await WorkingCopyViewModel(repository: mock)
        await viewModel.refresh()
        let count = await viewModel.status.count
        XCTAssertGreaterThan(count, 0)
    }
}
```
