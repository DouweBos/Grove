---
"grove": patch
---

- Error and warning banners can be dismissed and stay dismissed when the repository refreshes, and Blame and CI artifacts offer their Retry buttons again.
- "Open Blame at This Revision" in File History opens Blame at that commit, also from before the file was renamed.
- GroveKit, for apps that use it: additions only. `HistoryViewModel.fileHistory(path:)` with `onOpenBlame`, and ways to dismiss the Blame, File History, merge status and Git LFS banners. A dismissed refresh error stays dismissed until a read works or fails differently.
