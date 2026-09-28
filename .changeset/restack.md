---
"grove": minor
---

- Restack a stack in one click from the Stack tab: Restack moves only the branches that drifted from their parent, Sync fetches and moves the whole stack onto the new trunk, and Restack from Here moves one branch and everything on it. Branches checked out in other worktrees are restacked there. A conflict pauses the cascade in Changes, where Continue picks it up and Abort puts every branch back.
