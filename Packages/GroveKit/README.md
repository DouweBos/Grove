# GroveKit

The git engine and headless view models shared by Grove and Argus.

- No SwiftUI or AppKit in the engine. Views stay in each app.
- Git and worktree file access run through a pluggable `GitRunner`: `LocalGitRunner` runs git on this Mac; a remote runner can slot in later.

Grove uses this folder as a local package. Other apps depend on the Grove repository by URL; its root `Package.swift` exposes the same `GroveKit` product.

```sh
swift build
swift test
```
