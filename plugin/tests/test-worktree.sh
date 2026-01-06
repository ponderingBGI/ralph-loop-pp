#!/bin/bash
#
# Tests for worktree creation and cleanup
#
# Tests:
# - Worktree creation creates proper directory structure
# - Worktree creation creates correct branch
# - Environment files are copied
# - node_modules symlink is created (if exists)
# - Cleanup removes worktree properly
# - Cleanup removes branch
# - Cleanup handles missing worktrees gracefully
# - --all flag cleans everything
#

# shellcheck source=./run-tests.sh
# Assertions and exports are loaded from run-tests.sh

CREATE_SCRIPT="$PLUGIN_DIR/scripts/create-worktree.sh"
CLEANUP_SCRIPT="$PLUGIN_DIR/scripts/cleanup-worktree.sh"

setup() {
  # Ensure scripts are executable
  chmod +x "$CREATE_SCRIPT" "$CLEANUP_SCRIPT"

  # Create a test session directory that won't conflict
  export TEST_SESSION="test-wt-$$"

  # Clean up any leftover test worktrees
  if [[ -d "$TEST_WORKTREE_BASE/$TEST_SESSION" ]]; then
    rm -rf "$TEST_WORKTREE_BASE/$TEST_SESSION"
  fi

  # Clean up any leftover branches
  git branch | grep "ralph-plus/$TEST_SESSION" | xargs -I {} git branch -D {} 2>/dev/null || true
}

teardown() {
  # Clean up test worktrees and branches
  if [[ -d "$TEST_WORKTREE_BASE/$TEST_SESSION" ]]; then
    # Use the cleanup script to clean up
    "$CLEANUP_SCRIPT" "$TEST_SESSION" 2>/dev/null || true
  fi

  # Fallback cleanup
  rm -rf "$TEST_WORKTREE_BASE/$TEST_SESSION" 2>/dev/null || true
  git branch | grep "ralph-plus/$TEST_SESSION" | xargs -I {} git branch -D {} 2>/dev/null || true
  git worktree prune 2>/dev/null || true
}

# Test: create-worktree.sh requires session_id argument
test_create_requires_session_id() {
  local output
  local exit_code

  output=$("$CREATE_SCRIPT" 2>&1) && exit_code=0 || exit_code=$?

  assert_ne 0 "$exit_code" "Should fail without arguments"
  assert_contains "$output" "Usage" "Should show usage message"
}

# Test: create-worktree.sh requires worker_num argument
test_create_requires_worker_num() {
  local output
  local exit_code

  output=$("$CREATE_SCRIPT" "test-session" 2>&1) && exit_code=0 || exit_code=$?

  assert_ne 0 "$exit_code" "Should fail without worker num"
  assert_contains "$output" "Usage" "Should show usage message"
}

# Test: create-worktree.sh creates directory structure
test_create_worktree_creates_directory() {
  local output
  local worktree_path

  cd "$REPO_ROOT"
  output=$("$CREATE_SCRIPT" "$TEST_SESSION" "1" 2>&1)
  worktree_path="$TEST_WORKTREE_BASE/$TEST_SESSION/worker-1"

  assert_dir_exists "$worktree_path" "Worktree directory should be created"
  assert_contains "$output" "Worktree created successfully" "Should report success"
}

# Test: create-worktree.sh creates correct branch
test_create_worktree_creates_branch() {
  local branch_name="ralph-plus/$TEST_SESSION/worker-2"

  cd "$REPO_ROOT"
  "$CREATE_SCRIPT" "$TEST_SESSION" "2" >/dev/null 2>&1

  # Check if branch exists
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    return 0
  else
    echo "  Branch not found: $branch_name"
    return 1
  fi
}

# Test: create-worktree.sh is idempotent (re-running works)
test_create_worktree_idempotent() {
  cd "$REPO_ROOT"

  # Create worktree twice
  "$CREATE_SCRIPT" "$TEST_SESSION" "3" >/dev/null 2>&1
  local output
  output=$("$CREATE_SCRIPT" "$TEST_SESSION" "3" 2>&1)

  assert_contains "$output" "Worktree created successfully" "Second creation should succeed"
  assert_dir_exists "$TEST_WORKTREE_BASE/$TEST_SESSION/worker-3" "Directory should exist after recreation"
}

# Test: create-worktree.sh copies .claude directory
test_create_worktree_copies_claude_dir() {
  cd "$REPO_ROOT"

  # Create a temporary .claude directory if needed
  local had_claude_dir=false
  if [[ -d ".claude" ]]; then
    had_claude_dir=true
  else
    mkdir -p .claude
    echo "test" > .claude/test-marker
  fi

  "$CREATE_SCRIPT" "$TEST_SESSION" "4" >/dev/null 2>&1
  local worktree_path="$TEST_WORKTREE_BASE/$TEST_SESSION/worker-4"

  if [[ -d "$worktree_path/.claude" ]]; then
    # Clean up temp marker if we created it
    if [[ "$had_claude_dir" == "false" ]]; then
      rm -rf .claude
    fi
    return 0
  else
    if [[ "$had_claude_dir" == "false" ]]; then
      rm -rf .claude
    fi
    echo "  .claude directory not copied to worktree"
    return 1
  fi
}

# Test: create-worktree.sh outputs the worktree path
test_create_worktree_outputs_path() {
  cd "$REPO_ROOT"

  local output
  output=$("$CREATE_SCRIPT" "$TEST_SESSION" "5" 2>&1)
  local expected_path="$TEST_WORKTREE_BASE/$TEST_SESSION/worker-5"

  # The last line should be the path
  local last_line
  last_line=$(echo "$output" | tail -1)

  assert_eq "$expected_path" "$last_line" "Last line should be worktree path"
}

# Test: cleanup-worktree.sh shows usage without arguments
test_cleanup_shows_usage() {
  local output
  local exit_code

  output=$("$CLEANUP_SCRIPT" 2>&1) && exit_code=0 || exit_code=$?

  assert_ne 0 "$exit_code" "Should fail without arguments"
  assert_contains "$output" "Usage" "Should show usage"
}

# Test: cleanup-worktree.sh removes specific worker
test_cleanup_removes_specific_worker() {
  cd "$REPO_ROOT"

  # Create two workers
  "$CREATE_SCRIPT" "$TEST_SESSION" "6" >/dev/null 2>&1
  "$CREATE_SCRIPT" "$TEST_SESSION" "7" >/dev/null 2>&1

  # Clean up only worker 6
  "$CLEANUP_SCRIPT" "$TEST_SESSION" "6" >/dev/null 2>&1

  # Worker 6 should be gone, worker 7 should remain
  if [[ -d "$TEST_WORKTREE_BASE/$TEST_SESSION/worker-6" ]]; then
    echo "  Worker 6 directory still exists"
    return 1
  fi

  assert_dir_exists "$TEST_WORKTREE_BASE/$TEST_SESSION/worker-7" "Worker 7 should still exist"
}

# Test: cleanup-worktree.sh removes entire session
test_cleanup_removes_session() {
  cd "$REPO_ROOT"

  # Create workers
  "$CREATE_SCRIPT" "$TEST_SESSION" "8" >/dev/null 2>&1
  "$CREATE_SCRIPT" "$TEST_SESSION" "9" >/dev/null 2>&1

  # Clean up entire session
  "$CLEANUP_SCRIPT" "$TEST_SESSION" >/dev/null 2>&1

  if [[ -d "$TEST_WORKTREE_BASE/$TEST_SESSION" ]]; then
    echo "  Session directory still exists"
    return 1
  fi

  return 0
}

# Test: cleanup-worktree.sh removes branches
test_cleanup_removes_branches() {
  cd "$REPO_ROOT"

  local branch_name="ralph-plus/$TEST_SESSION/worker-10"

  # Create worktree
  "$CREATE_SCRIPT" "$TEST_SESSION" "10" >/dev/null 2>&1

  # Verify branch exists
  if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo "  Branch was not created"
    return 1
  fi

  # Clean up
  "$CLEANUP_SCRIPT" "$TEST_SESSION" "10" >/dev/null 2>&1

  # Branch should be gone
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo "  Branch still exists after cleanup"
    return 1
  fi

  return 0
}

# Test: cleanup-worktree.sh handles missing worktree gracefully
test_cleanup_handles_missing_worktree() {
  cd "$REPO_ROOT"

  local output
  local exit_code

  # Try to clean up non-existent worktree
  output=$("$CLEANUP_SCRIPT" "nonexistent-session" "99" 2>&1) && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Should not fail on missing worktree"
  assert_contains "$output" "not found" "Should report worktree not found"
}

# Test: cleanup-worktree.sh --all cleans everything
test_cleanup_all() {
  cd "$REPO_ROOT"

  # Create multiple sessions
  "$CREATE_SCRIPT" "${TEST_SESSION}-all1" "1" >/dev/null 2>&1
  "$CREATE_SCRIPT" "${TEST_SESSION}-all2" "1" >/dev/null 2>&1

  # Clean up all
  "$CLEANUP_SCRIPT" --all >/dev/null 2>&1

  # Base directory should be gone or empty
  if [[ -d "$TEST_WORKTREE_BASE/${TEST_SESSION}-all1" ]] || \
     [[ -d "$TEST_WORKTREE_BASE/${TEST_SESSION}-all2" ]]; then
    echo "  Some test session directories still exist"
    return 1
  fi

  return 0
}

# Test: worktree is a valid git repository
test_worktree_is_git_repo() {
  cd "$REPO_ROOT"

  "$CREATE_SCRIPT" "$TEST_SESSION" "11" >/dev/null 2>&1
  local worktree_path="$TEST_WORKTREE_BASE/$TEST_SESSION/worker-11"

  # Check if it's a git worktree
  if git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  else
    echo "  Worktree is not a valid git repository"
    return 1
  fi
}

# Test: worktree is on the correct branch
test_worktree_on_correct_branch() {
  cd "$REPO_ROOT"

  "$CREATE_SCRIPT" "$TEST_SESSION" "12" >/dev/null 2>&1
  local worktree_path="$TEST_WORKTREE_BASE/$TEST_SESSION/worker-12"
  local expected_branch="ralph-plus/$TEST_SESSION/worker-12"

  local actual_branch
  actual_branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD)

  assert_eq "$expected_branch" "$actual_branch" "Worktree should be on correct branch"
}
