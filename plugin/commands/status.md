---
name: optimize-status
description: Show the current status of ralph-loop++ optimization session
allowed-tools: Read, Bash
---

# Ralph-Loop++ Status

Display the current status of any active optimization session.

## Check for Active Session

Read `.claude/ralph-plus.local.md` and parse the YAML frontmatter.

## Display Information

If no active session:
```
No active ralph-loop++ session.
Use /optimize <task> to start a new optimization.
```

If active session found, display:

```
=== Ralph-Loop++ Status ===

Session: {session_id}
Started: {started_at}
Phase: {phase}

Task: {task}
Target: {target}
Metric: {metric}
Goal: {goal}

Baseline: {baseline_metric}
Best so far: {best_metric}

Workers:
  - Worker 1: {worktree_path}
    Branch: {branch}
    Iterations: {iterations}/20
    Best metric: {best_metric}

  - Worker 2: {worktree_path}
    Branch: {branch}
    Iterations: {iterations}/20
    Best metric: {best_metric}

Progress:
{phase-specific progress information}
```

## Check Worker Activity

```bash
# Check if worker processes are running
pgrep -f "ralph-plus" || echo "No active worker processes"

# Check worktree status
git worktree list | grep ralph-plus
```

Report any anomalies (crashed workers, missing worktrees, etc.)
