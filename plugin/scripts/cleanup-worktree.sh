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

# ============================================================================
# Safe rm function (prevents accidental deletion of important paths)
# ============================================================================
safe_rm() {
  local path="$1"

  # Never delete empty or root paths
  if [[ -z "$path" || "$path" == "/" ]]; then
    echo "Error: Refusing to delete empty or root path" >&2
    return 1
  fi

  # Resolve to absolute path
  local real_path
  real_path=$(realpath "$path" 2>/dev/null) || {
    echo "Warning: Cannot resolve path: $path" >&2
    return 1
  }

  # Verify path is within expected worktree base
  if [[ ! "$real_path" =~ ^/var/tmp/ralph-plus-worktrees(/|$) ]]; then
    echo "Error: Refusing to delete path outside worktree base: $real_path" >&2
    return 1
  fi

  # Safe to delete
  rm -rf -- "$path"
}

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
  git worktree remove "$path" --force 2>/dev/null || safe_rm "$path"

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
  safe_rm "$session_path"

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
  safe_rm "$WORKTREE_BASE"

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

    # Validate inputs before using them in paths
    validate_session_id "$SESSION_ID"

    if [[ -n "$WORKER_NUM" ]]; then
      validate_worker_num "$WORKER_NUM"
      # Clean up specific worker
      cleanup_worktree "${WORKTREE_BASE}/${SESSION_ID}/worker-${WORKER_NUM}"
    else
      # Clean up entire session
      cleanup_session "$SESSION_ID"
    fi
    ;;
esac
