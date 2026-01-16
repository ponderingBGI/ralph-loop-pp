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

Use the cleanup script for safe worktree removal:
```bash
# If session ID is known (from state file):
./plugin/scripts/cleanup-worktree.sh {session_id}

# Or to clean up ALL ralph-loop++ worktrees:
./plugin/scripts/cleanup-worktree.sh --all
```

The cleanup script handles:
- Safe path validation (prevents accidental deletion)
- Proper worktree removal
- Branch cleanup with whitespace handling
- Cross-platform compatibility

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
