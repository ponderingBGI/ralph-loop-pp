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

SESSION_ID="${1:?Usage: create-worktree.sh <session_id> <worker_num>}"
WORKER_NUM="${2:?Usage: create-worktree.sh <session_id> <worker_num>}"

WORKTREE_BASE="/var/tmp/ralph-plus-worktrees"
WORKTREE_PATH="${WORKTREE_BASE}/${SESSION_ID}/worker-${WORKER_NUM}"
BRANCH_NAME="ralph-plus/${SESSION_ID}/worker-${WORKER_NUM}"

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

# Copy .claude directory for plugin access
if [[ -d ".claude" ]]; then
  echo "  Copying .claude configuration..."
  cp -r .claude "$WORKTREE_PATH/"
fi

echo "Worktree created successfully!"
echo "$WORKTREE_PATH"
