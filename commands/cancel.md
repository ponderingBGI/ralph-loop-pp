---
name: cancel-optimize
description: Cancel the active ralph-loop++ optimization session
allowed-tools: Read, Bash, Glob
---

# Cancel Ralph-Loop++ Session

Cancel any active optimization session and clean up resources.

## Steps

1. Check for active session by reading `.claude/ralph-plus.local.md`
2. If no active session, inform user and exit
3. If active session found:
   - Kill any running worker processes
   - Delete all worktrees created for this session
   - Mark the session as cancelled in the state file
   - Report what was cleaned up

## Cleanup Process

```bash
# Find and remove worktrees
git worktree list | grep "ralph-plus" | awk '{print $1}' | xargs -I {} git worktree remove {} --force 2>/dev/null || true

# Clean up branches
git branch | grep "ralph-plus/" | xargs -I {} git branch -D {} 2>/dev/null || true
```

## State Update

Update the state file:
```yaml
active: false
cancelled_at: "{timestamp}"
phase: "cancelled"
```

Report to user:
- Session ID that was cancelled
- Number of worktrees cleaned up
- Any partial progress that was saved
