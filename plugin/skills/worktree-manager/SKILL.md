# Worktree Manager Skill

Manages git worktrees for isolated worker environments in ralph-loop++.

## Operations

### Create Worktree

Create a new isolated worktree for a worker:

```bash
# Generate unique branch name
SESSION_ID="$1"
WORKER_NUM="$2"
WORKTREE_BASE="/var/tmp/ralph-plus-worktrees"
WORKTREE_PATH="${WORKTREE_BASE}/${SESSION_ID}/worker-${WORKER_NUM}"
BRANCH_NAME="ralph-plus/${SESSION_ID}/worker-${WORKER_NUM}"

# Create base directory
mkdir -p "$(dirname "$WORKTREE_PATH")"

# Create worktree with new branch
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"

# Copy environment files
for env_file in .env .env.local .env.development .env.development.local; do
  if [[ -f "$env_file" ]]; then
    cp "$env_file" "$WORKTREE_PATH/"
  fi
done

# Copy node_modules symlink (faster than npm install)
if [[ -d "node_modules" ]]; then
  ln -s "$(pwd)/node_modules" "$WORKTREE_PATH/node_modules"
fi

echo "$WORKTREE_PATH"
```

### List Worktrees

List all ralph-loop++ worktrees:

```bash
git worktree list | grep "ralph-plus"
```

### Remove Worktree

Clean up a specific worktree:

```bash
WORKTREE_PATH="$1"
BRANCH_NAME=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD)

# Remove the worktree
git worktree remove "$WORKTREE_PATH" --force

# Delete the branch
git branch -D "$BRANCH_NAME" 2>/dev/null || true
```

### Cleanup All Session Worktrees

Remove all worktrees for a session:

```bash
SESSION_ID="$1"
WORKTREE_BASE="/var/tmp/ralph-plus-worktrees/${SESSION_ID}"

# Remove each worktree
for worktree in "$WORKTREE_BASE"/worker-*; do
  if [[ -d "$worktree" ]]; then
    git worktree remove "$worktree" --force 2>/dev/null || true
  fi
done

# Remove base directory
rm -rf "$WORKTREE_BASE"

# Clean up branches
git branch | grep "ralph-plus/${SESSION_ID}" | xargs -I {} git branch -D {} 2>/dev/null || true
```

## Worktree Locations

- **Base**: `/var/tmp/ralph-plus-worktrees/`
- **Session**: `/var/tmp/ralph-plus-worktrees/{session_id}/`
- **Worker**: `/var/tmp/ralph-plus-worktrees/{session_id}/worker-{n}/`

## Branch Naming

- Pattern: `ralph-plus/{session_id}/worker-{n}`
- Example: `ralph-plus/rp-1704567890123/worker-1`

## Environment Handling

When creating a worktree, copy:
- `.env` - Production/default environment
- `.env.local` - Local overrides
- `.env.development` - Development settings
- `.env.development.local` - Local dev overrides
- `.env.test` - Test environment (if running tests)

## Node Modules Strategy

For Node.js projects, there are two strategies:

### Symlink (Fast, works for most cases)
```bash
ln -s "$(pwd)/node_modules" "$WORKTREE_PATH/node_modules"
```

### Full Install (Needed if dependencies might change)
```bash
cd "$WORKTREE_PATH" && npm install
```

## Error Handling

### Worktree Already Exists
```bash
if [[ -d "$WORKTREE_PATH" ]]; then
  echo "Worktree already exists, removing first"
  git worktree remove "$WORKTREE_PATH" --force
fi
```

### Branch Already Exists
```bash
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  echo "Branch already exists, deleting first"
  git branch -D "$BRANCH_NAME"
fi
```

### Dirty Worktree on Cleanup
```bash
# Force removal even with uncommitted changes
git worktree remove "$WORKTREE_PATH" --force
```

## Usage in Ralph-Loop++

The orchestrator uses this skill to:
1. Create worktrees before spawning workers
2. Pass worktree paths to worker agents
3. Clean up all worktrees after integration complete
4. Handle recovery after crashes

## Troubleshooting

### "fatal: '$PATH' is already checked out"
Another worktree has the same branch. Use unique branch names per session/worker.

### "fatal: '$WORKTREE_PATH' is a main working tree"
Trying to remove the main repository. Check path is correct.

### Orphaned Worktrees
If worktrees exist but aren't in `git worktree list`:
```bash
git worktree prune
```
