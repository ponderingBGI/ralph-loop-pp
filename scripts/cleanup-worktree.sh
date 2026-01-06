#!/bin/bash
#
# Clean up ralph-loop++ worktrees
#
# Usage:
#   cleanup-worktree.sh <session_id>          # Clean up all worktrees for a session
#   cleanup-worktree.sh <session_id> <worker> # Clean up specific worker
#   cleanup-worktree.sh --all                 # Clean up ALL ralph-loop++ worktrees
#

set -euo pipefail

WORKTREE_BASE="/var/tmp/ralph-plus-worktrees"

cleanup_worktree() {
  local path="$1"
  local branch

  if [[ ! -d "$path" ]]; then
    echo "  Worktree not found: $path"
    return 0
  fi

  # Get branch name
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  echo "  Removing worktree: $path"
  git worktree remove "$path" --force 2>/dev/null || rm -rf "$path"

  if [[ -n "$branch" && "$branch" == ralph-plus/* ]]; then
    echo "  Deleting branch: $branch"
    git branch -D "$branch" 2>/dev/null || true
  fi
}

cleanup_session() {
  local session_id="$1"
  local session_path="${WORKTREE_BASE}/${session_id}"

  echo "Cleaning up session: $session_id"

  if [[ ! -d "$session_path" ]]; then
    echo "  Session directory not found: $session_path"
    return 0
  fi

  # Clean up each worker
  for worktree in "$session_path"/worker-*; do
    if [[ -d "$worktree" ]]; then
      cleanup_worktree "$worktree"
    fi
  done

  # Remove session directory
  rm -rf "$session_path"

  # Clean up any orphaned branches
  git branch | grep "ralph-plus/${session_id}" | xargs -I {} git branch -D {} 2>/dev/null || true

  echo "Session cleanup complete!"
}

cleanup_all() {
  echo "Cleaning up ALL ralph-loop++ worktrees..."

  # List all ralph-plus worktrees
  git worktree list | grep "ralph-plus" | while read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    cleanup_worktree "$path"
  done

  # Remove base directory
  rm -rf "$WORKTREE_BASE"

  # Clean up all ralph-plus branches
  git branch | grep "ralph-plus/" | xargs -I {} git branch -D {} 2>/dev/null || true

  # Prune worktree references
  git worktree prune

  echo "Full cleanup complete!"
}

# Main
case "${1:-}" in
  --all)
    cleanup_all
    ;;
  "")
    echo "Usage:"
    echo "  cleanup-worktree.sh <session_id>          # Clean up session"
    echo "  cleanup-worktree.sh <session_id> <worker> # Clean up specific worker"
    echo "  cleanup-worktree.sh --all                 # Clean up everything"
    exit 1
    ;;
  *)
    SESSION_ID="$1"
    WORKER_NUM="${2:-}"

    if [[ -n "$WORKER_NUM" ]]; then
      # Clean up specific worker
      cleanup_worktree "${WORKTREE_BASE}/${SESSION_ID}/worker-${WORKER_NUM}"
    else
      # Clean up entire session
      cleanup_session "$SESSION_ID"
    fi
    ;;
esac
