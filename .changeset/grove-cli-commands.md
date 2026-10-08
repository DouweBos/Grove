---
"grove": minor
---

The `grove` command does more from Terminal, for you and for scripts and agents handing work over to Grove:
- `grove history [branch]`, `grove blame <file>` and `grove stack [branch]` open Grove right on that view
- `grove stacks`, `grove branches` and `grove prs` print the repository's stacks, branches and open pull requests, with `--json` for scripts
- `grove -C <path>` runs it for another folder, and `grove help` lists everything
