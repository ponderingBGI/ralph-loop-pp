# Ralph-Loop++ Plugin

This is the ralph-loop++ Claude Code plugin - an advanced multi-agent optimization system.

## Project Structure

```
ralph-loop++/
├── .claude-plugin/plugin.json   # Plugin metadata
├── commands/                    # Slash commands
│   ├── optimize.md             # /optimize - main entry
│   ├── cancel.md               # /cancel-optimize
│   └── status.md               # /optimize-status
├── agents/                      # Agent definitions
│   ├── orchestrator.md
│   ├── test-architect.md
│   ├── worker.md
│   ├── evaluator.md
│   └── integrator.md
├── skills/                      # Agent skills
│   ├── worktree-manager/
│   ├── metric-runner/
│   └── progress-tracker/
├── hooks/                       # Event hooks
│   ├── hooks.json
│   └── worker-stop-hook.sh
└── scripts/                     # Helper scripts
    ├── create-worktree.sh
    ├── cleanup-worktree.sh
    └── run-test.sh
```

## Development Guidelines

- Commands are markdown files with YAML frontmatter
- Agents are markdown files describing agent behavior
- Skills are in `skills/<name>/SKILL.md` format
- Scripts should be POSIX-compatible bash

## Testing

To test the plugin locally:
1. Install: `claude plugins install .`
2. Run: `/optimize <test task>`
3. Check: `/optimize-status`
4. Clean: `/cancel-optimize`

## Agent Guidelines

@agents.md
