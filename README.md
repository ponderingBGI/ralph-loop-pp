# Ralph-Loop++

Multi-agent optimization using Ralph Wiggum technique with parallel workers in isolated git worktrees.

## Install

```bash
/plugin marketplace add ponderingBGI/ralph-loop-pp
/plugin install ralph-loop-pp@ralph-loop-pp
/plugin install ralph-wiggum@claude-plugins-official  # Required dependency
```

## Usage

```bash
/optimize <goal>           # Start optimization
/optimize-status           # Check progress
/cancel-optimize           # Stop and cleanup
```

Examples:
```bash
/optimize Reduce API latency to under 50ms p95
/optimize Fix flaky tests in auth module
/optimize Increase test coverage to 90%
```

## How It Works

1. **Parse** - Extract goals from natural language
2. **Test** - Create verification test for metric
3. **Explore** - Workers try approaches in worktrees
4. **Evaluate** - Check for quality and "spirit" compliance
5. **Integrate** - Clean implementation following conventions

State saved to `.claude/ralph-plus.local.md` for recovery.

## Requirements

- Claude Code CLI
- Ralph Wiggum plugin
- Git

## License

MIT - [Ralph Wiggum technique](https://ghuntley.com/ralph/) by Geoffrey Huntley
