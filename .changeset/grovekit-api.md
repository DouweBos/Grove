---
"grove": minor
---

GroveKit, for apps that use it:
- `ShellResult` has a public initializer, and `GitRunner`'s defaults are nonisolated, so runners outside GroveKit build without spelling them out.
