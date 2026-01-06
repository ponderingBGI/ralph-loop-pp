# Ralph-Loop++ Agent Guidelines

This document defines how agents should operate within the ralph-loop++ plugin.

## Agent Hierarchy

```
Orchestrator (opus)
├── Test Architect (sonnet)
├── Worker 1 (configurable, in worktree)
├── Worker 2 (configurable, in worktree)
├── Worker N...
├── Evaluator (opus)
└── Integrator (sonnet)
```

## Communication Protocol

Agents communicate through:
1. **State file**: `.claude/ralph-plus.local.md` (YAML frontmatter + markdown body)
2. **Git commits**: Workers document their progress in commit messages
3. **File artifacts**: Workers create `OPTIMIZATION_LOG.md` in their worktree

## Tool Access by Agent

### Orchestrator
- All tools available
- Task tool for spawning sub-agents
- Full read/write access

### Test Architect
- Read, Write, Edit, Bash, Grep, Glob
- No deployment or destructive tools
- Focus on test infrastructure

### Worker
- Curated by Orchestrator based on task
- Always: Read, Edit, Write, Bash (limited), Grep, Glob
- Research: Context7, WebSearch, WebFetch (if available)
- Never: Deployment, database, or production tools

### Evaluator
- Read-only operations
- Grep, Glob for code analysis
- Bash for running tests
- No file modifications

### Integrator
- Read, Write, Edit, Bash, Grep, Glob
- No deployment tools
- Focus on clean implementation

## Worker Iteration Protocol

Each worker iteration:
1. Read last test result
2. Analyze progress vs target
3. If target met → output `<promise>GOAL ACHIEVED: {value}</promise>`
4. If not → make improvements
5. Run unit tests
6. Run verification test
7. Commit changes
8. Document in OPTIMIZATION_LOG.md

## Completion Signals

Workers signal completion to Ralph loop:
- `<promise>GOAL ACHIEVED: {metric}</promise>` - Target met
- `<promise>BEST EFFORT: {metric}</promise>` - Max iterations reached
- `<promise>BLOCKED: {reason}</promise>` - Cannot proceed

## State Persistence

Always update state file after:
- Phase transitions
- Metric measurements
- Worker spawn/complete
- Evaluation decisions
- Errors

## Error Handling

Agents should:
- Log errors to state file
- Attempt recovery when possible
- Report clearly when blocked
- Never leave orphaned resources
