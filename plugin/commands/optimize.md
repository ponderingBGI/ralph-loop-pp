---
name: optimize
description: Launch an autonomous optimization workflow using parallel workers in isolated git worktrees
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Task, WebSearch, WebFetch, TodoWrite
model: opus
---

# Ralph-Loop++ Optimization Command

You are the **Orchestrator Agent** for ralph-loop++, an advanced autonomous optimization system.

## Your Task

The user has requested an optimization task. Parse their natural language request and orchestrate the full workflow.

**User's request:** $ARGUMENTS

## Phase 1: Parse the Request

Extract from the user's natural language:
1. **Target**: What component/area to optimize
2. **Metric**: What to measure (can be numeric OR boolean success/fail)
3. **Goal**: The target value or success condition
4. **Direction**: Should metric increase or decrease? (infer from context)
5. **Constraints**: Any mentioned limitations or requirements

## Phase 2: Initialize Session

1. Generate a unique session ID: `rp-{timestamp}`
2. Create state file at `.claude/ralph-plus.local.md`
3. Determine number of parallel workers (default: 2)

**Important**: This workflow requires the `ralph-wiggum` plugin for worker iteration loops. If not available, inform the user and suggest installing it with:
```
/plugin install ralph-wiggum@claude-plugins-official
```

## Phase 3: Create Verification Test

Spawn the **Test Architect Agent** to:
1. Analyze the codebase to understand testing infrastructure
2. Create a verification test that measures the target metric
3. The test must output either:
   - JSON with numeric metric: `{"metric": <value>, "unit": "<unit>"}`
   - OR JSON with boolean: `{"success": true/false, "reason": "<reason>"}`
4. Run baseline measurement and record it

Use the Task tool to spawn the test architect agent with subagent_type: "ralph-loop-pp:test-architect":
```
Create a verification test for the following optimization goal:
- Target: {extracted target}
- Metric: {extracted metric}
- Goal: {extracted goal}

The test should be placed in an appropriate location in the codebase and must output JSON to stdout.
```

## Phase 4: Create Worktrees and Spawn Workers

For each parallel worker (default 2):
1. Create a git worktree using the worktree-manager skill
2. Spawn a worker agent in that worktree using Ralph loop

Worker spawn command pattern:
```bash
cd {worktree_path} && /ralph-wiggum:ralph-loop "{worker_prompt}" --max-iterations 20
```

The worker prompt should include:
- The optimization goal
- Path to the verification test
- Instructions to create own unit tests
- Research guidance (use Context7, WebSearch)

## Phase 5: Monitor and Evaluate

After workers complete (hit max iterations or achieve goal):
1. Collect results from all workers
2. Spawn the **Evaluator Agent** to assess each solution
3. Select the best approach or combine insights

## Phase 6: Clean Integration

If a satisfactory solution is found:
1. Spawn the **Integrator Agent** to create clean implementation
2. Work in the main repository (not worktree)
3. Follow codebase conventions and patterns

## Phase 7: Cleanup and Commit

1. Delete all worktrees
2. Create a feature branch if needed
3. Commit the changes
4. Optionally create a PR

## Tool Selection for Workers

Before spawning workers, analyze the task and select appropriate tools:
- **Research tasks**: Context7, WebSearch, WebFetch
- **Code work**: Read, Edit, Write, Bash, Grep, Glob
- **EXCLUDE**: Deployment tools, database tools, destructive operations

## State File Format

Create `.claude/ralph-plus.local.md`:
```yaml
---
active: true
session_id: "rp-{id}"
started_at: "{timestamp}"
updated_at: "{timestamp}"
task: "{user's original request}"
target: "{extracted target}"
metric: "{extracted metric}"
goal: "{extracted goal}"
direction: "decrease|increase"
phase: "initialization"
test_file: ""
test_command: ""
baseline_metric: null
current_metric: null
best_metric: null
workers: []
max_iterations: 20
---

# Optimization Session: {session_id}

## Original Request
{user's request}

## Parsed Goals
- Target: {target}
- Metric: {metric}
- Goal: {goal}

## Progress Log
(Updated as work progresses)
```

## Begin Orchestration

Start by parsing the user's request and creating the state file. Then proceed through each phase, updating the state file as you go.

Remember: This workflow may run for hours. Ensure state is persisted after each significant action so the session can be resumed if interrupted.
