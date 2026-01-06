# Ralph-Loop++

An advanced Claude Code plugin for autonomous, long-running optimization tasks using the Ralph Wiggum technique with parallel workers and git worktree isolation.

## What is Ralph-Loop++?

Ralph-Loop++ extends the [Ralph Wiggum technique](https://ghuntley.com/ralph/) to create a sophisticated multi-agent optimization system. Give it an abstract but measurable goal in natural language, and it will:

1. **Create a verification test** to measure your optimization target
2. **Spawn parallel workers** in isolated git worktrees
3. **Iterate autonomously** until the goal is achieved
4. **Evaluate solutions** for quality and "spirit" compliance
5. **Integrate cleanly** following your codebase conventions
6. **Create a PR** with the optimized code

## Installation

```bash
# Install the plugin
claude plugins install github:user/ralph-loop++

# Requires the Ralph Wiggum plugin
claude plugins install ralph-wiggum@claude-plugins-official
```

## Usage

Just describe what you want to optimize in natural language:

```bash
# Performance optimization
/optimize Reduce the API response time for /users endpoint to under 50ms p95 latency

# Memory optimization
/optimize Improve GPU memory efficiency for the renderer - target under 800MB peak

# Bug fixing
/optimize Fix the flaky tests in the auth module so they pass consistently

# Code quality
/optimize Increase test coverage for the payment module to at least 90%

# General improvement
/optimize Make the dashboard load faster - it currently takes 3 seconds
```

### Other Commands

```bash
/optimize-status     # Check current progress
/cancel-optimize     # Stop all workers and clean up
```

## How It Works

### Architecture

```
User Task → Orchestrator → Test Architect → Parallel Workers
                ↓                ↓                ↓
            Evaluates      Creates Test      Ralph Loop
                ↓                ↓           (max 20 iter)
           Integrator ← Accept/Refine ← Metric Check
                ↓
         Clean Code → Commit → PR
```

### Agents

| Agent | Role |
|-------|------|
| **Orchestrator** | Parses request, coordinates workflow, manages state |
| **Test Architect** | Creates verification tests that measure the target metric |
| **Worker** | Explores solutions in isolated worktree using Ralph loop |
| **Evaluator** | Assesses worker solutions for quality and "spirit" |
| **Integrator** | Creates clean, production-ready implementation |

### Workflow

1. **Parse**: The orchestrator extracts goals from your natural language request
2. **Test**: A verification test is created to measure the target metric
3. **Explore**: 2-3 workers try different approaches in isolated worktrees
4. **Iterate**: Each worker runs in a Ralph loop (up to 20 iterations)
5. **Evaluate**: Solutions are checked for quality and genuine improvement
6. **Integrate**: The best approach is reimplemented following codebase conventions
7. **Commit**: Changes are committed and optionally a PR is created

## Features

### Natural Language Interface
No flags or complex syntax - just describe what you want to achieve.

### Parallel Workers
Multiple workers explore different approaches simultaneously. The evaluator picks the best solution or combines insights.

### Git Worktree Isolation
Workers operate in isolated worktrees, so experiments don't affect your main codebase.

### Spirit Compliance
The evaluator checks that solutions genuinely achieve the goal rather than "gaming" the metric.

### Automatic Tool Selection
The orchestrator curates which tools each worker can access based on the task, preventing misuse.

### State Persistence
Progress is saved to `.claude/ralph-plus.local.md`, enabling recovery if interrupted.

## Configuration

Ralph-Loop++ works with your existing Claude Code setup:

- **MCP Servers**: Uses whatever you have configured (Context7 and Exa recommended for research)
- **Permissions**: Inherits from your project's settings
- **Git**: Respects your git configuration and hooks

## Examples

### Performance Optimization

```bash
/optimize Reduce API response time for /users endpoint to under 50ms
```

**What happens:**
1. Creates a benchmark test hitting the endpoint
2. Worker 1 tries connection pooling
3. Worker 2 tries query optimization
4. Evaluator selects best approach
5. Integrator creates clean implementation
6. PR created with performance comparison

### Memory Leak Fix

```bash
/optimize Fix the memory leak in WebSocket connection handler - target under 100MB growth over 1000 connections
```

**What happens:**
1. Creates a stress test measuring memory growth
2. Workers investigate and fix different leak sources
3. Multiple cycles as evaluator finds edge cases
4. Final implementation with proper cleanup patterns

## State File

Progress is tracked in `.claude/ralph-plus.local.md`:

```yaml
---
active: true
session_id: "rp-1704567890123"
phase: "worker_exploration"
task: "Reduce API response time..."
baseline_metric: 120
best_metric: 65
workers:
  - id: 1
    iterations: 12
    best_metric: 65
    approach: "Connection pooling"
---
```

## Requirements

- Claude Code CLI
- [Ralph Wiggum plugin](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum)
- Git (for worktree management)

## Recommended MCP Servers

For best research capabilities:
- **Context7** - Library documentation lookup
- **Exa** - Semantic web/code search

## Cost Considerations

This plugin is designed for long-running, background operations. Costs depend on:
- Number of parallel workers (default: 2)
- Iterations per worker (max: 20)
- Evaluation cycles (default max: 3)
- Model used (Opus for orchestrator/evaluator, Sonnet for workers)

A typical optimization task might cost $10-50 depending on complexity.

## Troubleshooting

### "No active session"
Use `/optimize <task>` to start a new optimization.

### Workers not progressing
Check `/optimize-status` for current state. Workers might be stuck on research or hitting rate limits.

### Worktrees not cleaning up
Run: `./scripts/cleanup-worktree.sh --all`

### Test creation fails
The test architect couldn't create a suitable test. Try being more specific about what to measure.

## Contributing

Contributions welcome! Please open an issue to discuss significant changes.

## License

MIT

## Credits

- [Ralph Wiggum technique](https://ghuntley.com/ralph/) by Geoffrey Huntley
- Built for [Claude Code](https://claude.ai/claude-code)
