---
"grove": patch
---

- Unstaging or discarding selected lines changes exactly those lines.
- Hunk and line actions keep a missing newline at the end of a file, and work with renamed, added and deleted files and with paths that have spaces or other scripts.
- An action on a diff that is out of date is refused instead of changing other content.
- GroveKit, for apps that use it: no API changes. Hunk actions take hunks and lines as `diff(for:staged:ignoreWhitespace:)` returned them, paths from status and diffs come unquoted, and a staged rename's diff has its `oldPath`.
