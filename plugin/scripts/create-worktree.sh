#!/bin/bash
#
# Create a git worktree for a ralph-loop++ worker
#
# Usage: create-worktree.sh <session_id> <worker_num>
#
# Creates: /var/tmp/ralph-plus-worktrees/<session_id>/worker-<worker_num>
# Branch: ralph-plus/<session_id>/worker-<worker_num>
#

set -euo pipefail

# ============================================================================
# Input validation (prevents path traversal attacks)
# ============================================================================
validate_session_id() {
  local id="$1"
  # Session ID must be: rp-<timestamp> format (e.g., rp-1704567890123)
  if [[ ! "$id" =~ ^rp-[0-9]{10,15}$ ]]; then
    echo "Error: Invalid session ID format." >&2
    echo "Expected format: rp-<timestamp> (e.g., rp-1704567890123)" >&2
    exit 1
  fi
}

validate_worker_num() {
  local num="$1"
  # Worker number must be a positive integer (1-99)
  if [[ ! "$num" =~ ^[1-9][0-9]?$ ]]; then
    echo "Error: Invalid worker number." >&2
    echo "Expected: integer 1-99" >&2
    exit 1
  fi
}

SESSION_ID="${1:?Usage: create-worktree.sh <session_id> <worker_num>}"
WORKER_NUM="${2:?Usage: create-worktree.sh <session_id> <worker_num>}"

# Validate inputs before using them in paths
validate_session_id "$SESSION_ID"
validate_worker_num "$WORKER_NUM"

WORKTREE_BASE="/var/tmp/ralph-plus-worktrees"
WORKTREE_PATH="${WORKTREE_BASE}/${SESSION_ID}/worker-${WORKER_NUM}"
BRANCH_NAME="ralph-plus/${SESSION_ID}/worker-${WORKER_NUM}"

# Double-check the constructed path is within expected base (defense in depth)
if [[ ! "$WORKTREE_PATH" =~ ^/var/tmp/ralph-plus-worktrees/rp-[0-9]+/worker-[0-9]+$ ]]; then
  echo "Error: Constructed path failed validation check" >&2
  exit 1
fi

echo "Creating worktree for worker ${WORKER_NUM}..."
echo "  Path: ${WORKTREE_PATH}"
echo "  Branch: ${BRANCH_NAME}"

# Create base directory
mkdir -p "$(dirname "$WORKTREE_PATH")"

# Remove existing worktree if it exists
if [[ -d "$WORKTREE_PATH" ]]; then
  echo "  Removing existing worktree..."
  git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
fi

# Delete existing branch if it exists
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  echo "  Deleting existing branch..."
  git branch -D "$BRANCH_NAME" 2>/dev/null || true
fi

# Create worktree with new branch
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"

# Copy environment files
echo "  Copying environment files..."
for env_file in .env .env.local .env.development .env.development.local .env.test; do
  if [[ -f "$env_file" ]]; then
    cp "$env_file" "$WORKTREE_PATH/"
    echo "    Copied $env_file"
  fi
done

# Symlink node_modules if exists (faster than npm install)
if [[ -d "node_modules" ]]; then
  echo "  Symlinking node_modules..."
  ln -s "$(pwd)/node_modules" "$WORKTREE_PATH/node_modules"
fi

# Copy .claude directory for plugin access (but symlink state file to avoid duplication)
if [[ -d ".claude" ]]; then
  echo "  Setting up .claude configuration..."
  mkdir -p "$WORKTREE_PATH/.claude"

  # Copy static config files
  for config_file in CLAUDE.md agents.md settings.json settings.local.json; do
    if [[ -f ".claude/$config_file" ]]; then
      cp ".claude/$config_file" "$WORKTREE_PATH/.claude/"
      echo "    Copied $config_file"
    fi
  done

  # Symlink the state file to the main repo (shared state between workers)
  main_repo_root=$(pwd)
  if [[ -f ".claude/ralph-plus.local.md" ]]; then
    ln -sf "$main_repo_root/.claude/ralph-plus.local.md" "$WORKTREE_PATH/.claude/ralph-plus.local.md"
    echo "    Symlinked ralph-plus.local.md (shared state)"
  fi
fi

echo "Worktree created successfully!"
echo "$WORKTREE_PATH"
