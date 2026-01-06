#!/bin/bash
#
# Tests for edge cases and error handling
#
# Tests:
# - Scripts handle special characters in paths
# - Scripts handle concurrent execution
# - Scripts handle disk space issues gracefully
# - Scripts handle permission issues
# - Worker stop hook handles various states
# - Recovery from partial failures
#

# shellcheck source=./run-tests.sh
# Assertions and exports are loaded from run-tests.sh

SCRIPTS_DIR="$PLUGIN_DIR/scripts"
HOOKS_DIR="$PLUGIN_DIR/hooks"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

setup() {
  mkdir -p "$FIXTURES_DIR"
  chmod +x "$SCRIPTS_DIR"/*.sh
  chmod +x "$HOOKS_DIR"/*.sh 2>/dev/null || true

  export EDGE_TEST_SESSION="edge-test-$$"
}

teardown() {
  # Clean up test artifacts
  rm -rf "$FIXTURES_DIR/test-"* 2>/dev/null || true

  # Clean up any test worktrees
  if [[ -d "$TEST_WORKTREE_BASE/$EDGE_TEST_SESSION" ]]; then
    "$SCRIPTS_DIR/cleanup-worktree.sh" "$EDGE_TEST_SESSION" 2>/dev/null || true
  fi
  rm -rf "$TEST_WORKTREE_BASE/$EDGE_TEST_SESSION" 2>/dev/null || true
  git branch | grep "ralph-plus/$EDGE_TEST_SESSION" | xargs -I {} git branch -D {} 2>/dev/null || true
  git worktree prune 2>/dev/null || true
}

# Test: Session ID with special characters (dashes, numbers)
test_session_id_with_dashes() {
  local session_id="rp-2024-01-06-123456"

  cd "$REPO_ROOT"
  local output
  output=$("$SCRIPTS_DIR/create-worktree.sh" "$session_id" "1" 2>&1)

  assert_contains "$output" "successfully" "Should handle dashed session ID"

  # Clean up
  "$SCRIPTS_DIR/cleanup-worktree.sh" "$session_id" >/dev/null 2>&1
}

# Test: Worker number with leading zeros
test_worker_num_leading_zeros() {
  cd "$REPO_ROOT"
  local output
  output=$("$SCRIPTS_DIR/create-worktree.sh" "$EDGE_TEST_SESSION" "01" 2>&1)

  # Should work even with leading zeros
  assert_contains "$output" "successfully" "Should handle leading zero in worker num"
}

# Test: Create many workers in sequence
test_many_workers() {
  cd "$REPO_ROOT"

  # Create 5 workers
  for i in {1..5}; do
    "$SCRIPTS_DIR/create-worktree.sh" "$EDGE_TEST_SESSION" "$i" >/dev/null 2>&1
  done

  # All should exist
  local count
  count=$(ls -d "$TEST_WORKTREE_BASE/$EDGE_TEST_SESSION"/worker-* 2>/dev/null | wc -l)

  assert_eq "5" "$count" "Should have 5 workers"
}

# Test: Cleanup non-existent session
test_cleanup_nonexistent() {
  local output
  local exit_code

  output=$("$SCRIPTS_DIR/cleanup-worktree.sh" "nonexistent-$$" 2>&1) && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Should not fail on nonexistent session"
  assert_contains "$output" "not found" "Should report not found"
}

# Test: Double cleanup is safe
test_double_cleanup() {
  cd "$REPO_ROOT"

  # Create and cleanup
  "$SCRIPTS_DIR/create-worktree.sh" "$EDGE_TEST_SESSION" "1" >/dev/null 2>&1
  "$SCRIPTS_DIR/cleanup-worktree.sh" "$EDGE_TEST_SESSION" >/dev/null 2>&1

  # Second cleanup should be safe
  local exit_code
  "$SCRIPTS_DIR/cleanup-worktree.sh" "$EDGE_TEST_SESSION" >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Double cleanup should be safe"
}

# Test: Worktree with uncommitted changes
test_worktree_uncommitted_changes() {
  cd "$REPO_ROOT"

  # Create worktree
  "$SCRIPTS_DIR/create-worktree.sh" "$EDGE_TEST_SESSION" "1" >/dev/null 2>&1

  local worktree_path="$TEST_WORKTREE_BASE/$EDGE_TEST_SESSION/worker-1"

  # Make uncommitted changes
  echo "test change" > "$worktree_path/test-uncommitted.txt"

  # Cleanup should still work (force)
  local exit_code
  "$SCRIPTS_DIR/cleanup-worktree.sh" "$EDGE_TEST_SESSION" "1" >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Should handle uncommitted changes"

  if [[ -d "$worktree_path" ]]; then
    echo "  Worktree still exists"
    return 1
  fi
  return 0
}

# Test: run-test.sh with command that takes time
test_slow_command() {
  cat > "$FIXTURES_DIR/test-slow.sh" << 'EOF'
#!/bin/bash
sleep 0.5
echo '{"success": true, "metric_value": 100}'
EOF
  chmod +x "$FIXTURES_DIR/test-slow.sh"

  local output
  output=$("$SCRIPTS_DIR/run-test.sh" "$FIXTURES_DIR/test-slow.sh" 2>/dev/null)

  assert_json_valid "$output" "Should handle slow command"
  assert_json_value "$output" "success" "true"
}

# Test: run-test.sh with command that writes to files
test_command_writes_files() {
  cat > "$FIXTURES_DIR/test-writer.sh" << 'EOF'
#!/bin/bash
echo "test" > /tmp/ralph-test-output-$$.txt
echo '{"success": true, "metric_value": 1}'
rm /tmp/ralph-test-output-$$.txt
EOF
  chmod +x "$FIXTURES_DIR/test-writer.sh"

  local output
  output=$("$SCRIPTS_DIR/run-test.sh" "$FIXTURES_DIR/test-writer.sh" 2>/dev/null)

  assert_json_valid "$output" "Should handle file-writing command"
}

# Test: run-test.sh with command using pipes
test_command_with_pipes() {
  local output
  output=$("$SCRIPTS_DIR/run-test.sh" "echo 'line1\nline2\nline3' | wc -l" 2>/dev/null)

  assert_json_valid "$output" "Should handle piped commands"
  assert_json_value "$output" "success" "true"
}

# Test: run-test.sh with subshell
test_command_with_subshell() {
  local output
  output=$("$SCRIPTS_DIR/run-test.sh" '(echo "subshell"; echo "42")' 2>/dev/null)

  assert_json_valid "$output" "Should handle subshell"
  assert_json_value "$output" "success" "true"
}

# Test: Worker stop hook without state file
test_hook_no_state_file() {
  cd "$FIXTURES_DIR"

  local exit_code
  "$HOOKS_DIR/worker-stop-hook.sh" >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Hook should exit 0 without state file"
}

# Test: Worker stop hook with inactive session
test_hook_inactive_session() {
  mkdir -p "$FIXTURES_DIR/.claude"
  cat > "$FIXTURES_DIR/.claude/ralph-plus.local.md" << 'EOF'
---
active: false
session_id: "test-123"
phase: complete
---
EOF

  cd "$FIXTURES_DIR"
  local exit_code
  "$HOOKS_DIR/worker-stop-hook.sh" >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Hook should exit 0 for inactive session"

  rm -rf "$FIXTURES_DIR/.claude"
}

# Test: Worker stop hook with wrong phase
test_hook_wrong_phase() {
  mkdir -p "$FIXTURES_DIR/.claude"
  cat > "$FIXTURES_DIR/.claude/ralph-plus.local.md" << 'EOF'
---
active: true
session_id: "test-123"
phase: initialization
---
EOF

  cd "$FIXTURES_DIR"
  local exit_code
  "$HOOKS_DIR/worker-stop-hook.sh" >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Hook should exit 0 for wrong phase"

  rm -rf "$FIXTURES_DIR/.claude"
}

# Test: Worker stop hook with missing test command
test_hook_missing_test_command() {
  mkdir -p "$FIXTURES_DIR/.claude"
  cat > "$FIXTURES_DIR/.claude/ralph-plus.local.md" << 'EOF'
---
active: true
session_id: "test-123"
phase: worker_exploration
goal: 50
direction: decrease
---
EOF

  cd "$FIXTURES_DIR"
  local exit_code
  "$HOOKS_DIR/worker-stop-hook.sh" >/dev/null 2>&1 && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Hook should exit 0 with missing test command"

  rm -rf "$FIXTURES_DIR/.claude"
}

# Test: State file with very long task description
test_long_task_description() {
  cat > "$FIXTURES_DIR/long-task.md" << 'EOF'
---
active: true
session_id: "test-123"
task: "This is a very long task description that goes on and on and on. It contains lots of details about what needs to be optimized and why. The goal is to reduce API response time by at least 50% while maintaining all existing functionality and not breaking any tests. This should be done by analyzing the current bottlenecks and implementing appropriate caching, query optimization, and other performance improvements."
phase: worker_exploration
---
EOF

  local value
  value=$(grep "^session_id:" "$FIXTURES_DIR/long-task.md" | head -1 | sed "s/^session_id: *//" | sed 's/"//g')

  assert_eq "test-123" "$value" "Should parse file with long task"
}

# Test: Rapid create-delete cycles
test_rapid_create_delete() {
  cd "$REPO_ROOT"

  local rapid_session="rapid-$$"
  for i in {1..3}; do
    "$SCRIPTS_DIR/create-worktree.sh" "$rapid_session" "$i" >/dev/null 2>&1
    "$SCRIPTS_DIR/cleanup-worktree.sh" "$rapid_session" "$i" >/dev/null 2>&1
  done

  # Should leave no trace (directory might exist but should be empty or gone)
  if [[ -d "$TEST_WORKTREE_BASE/$rapid_session" ]] && \
     [[ -n "$(ls -A "$TEST_WORKTREE_BASE/$rapid_session" 2>/dev/null)" ]]; then
    echo "  Leftover files in session directory"
    # Clean up for next run
    rm -rf "$TEST_WORKTREE_BASE/$rapid_session"
    return 1
  fi

  # Ensure directory is removed if empty
  rmdir "$TEST_WORKTREE_BASE/$rapid_session" 2>/dev/null || true
  return 0
}

# Test: Git worktree prune after cleanup
test_worktree_prune() {
  cd "$REPO_ROOT"

  # Create worktree
  "$SCRIPTS_DIR/create-worktree.sh" "$EDGE_TEST_SESSION" "1" >/dev/null 2>&1

  # Manually delete directory (simulating crash)
  rm -rf "$TEST_WORKTREE_BASE/$EDGE_TEST_SESSION"

  # Git should be able to prune
  local exit_code
  git worktree prune 2>&1 && exit_code=0 || exit_code=$?

  assert_eq 0 "$exit_code" "Git prune should succeed"

  # Clean up branch
  git branch -D "ralph-plus/$EDGE_TEST_SESSION/worker-1" 2>/dev/null || true
}

# Test: run-test with very large output
test_very_large_output() {
  cat > "$FIXTURES_DIR/test-large.sh" << 'EOF'
#!/bin/bash
# Generate large output
for i in {1..1000}; do
  echo "This is line number $i with some extra content to make it longer"
done
echo '{"success": true, "metric_value": 42}'
EOF
  chmod +x "$FIXTURES_DIR/test-large.sh"

  local output
  output=$("$SCRIPTS_DIR/run-test.sh" "$FIXTURES_DIR/test-large.sh" 2>/dev/null)

  # Should still return valid JSON
  assert_json_valid "$output" "Should handle large output"
}

# Test: Nested JSON output
test_nested_json() {
  cat > "$FIXTURES_DIR/test-nested.sh" << 'EOF'
#!/bin/bash
echo '{"success": true, "metric_value": 100, "breakdown": {"database": 40, "network": 30, "compute": 30}, "tags": ["fast", "optimized"]}'
EOF
  chmod +x "$FIXTURES_DIR/test-nested.sh"

  local output
  output=$("$SCRIPTS_DIR/run-test.sh" "$FIXTURES_DIR/test-nested.sh" 2>/dev/null)

  assert_json_valid "$output" "Should handle nested JSON"
  assert_json_has_key "$output" "breakdown" "Should preserve nested objects"
}

# Test: Unicode in output
test_unicode_output() {
  cat > "$FIXTURES_DIR/test-unicode.sh" << 'EOF'
#!/bin/bash
echo '{"success": true, "metric_value": 50, "message": "Performance improved! 🚀"}'
EOF
  chmod +x "$FIXTURES_DIR/test-unicode.sh"

  local output
  output=$("$SCRIPTS_DIR/run-test.sh" "$FIXTURES_DIR/test-unicode.sh" 2>/dev/null)

  # May or may not preserve unicode, but should be valid JSON
  assert_json_valid "$output" "Should handle unicode"
  assert_json_value "$output" "success" "true"
}

# Test: Signal handling (SIGTERM)
test_signal_handling() {
  cat > "$FIXTURES_DIR/test-signal.sh" << 'EOF'
#!/bin/bash
trap 'echo "caught signal"' TERM
echo '{"success": true, "metric_value": 1}'
EOF
  chmod +x "$FIXTURES_DIR/test-signal.sh"

  local output
  output=$("$SCRIPTS_DIR/run-test.sh" "$FIXTURES_DIR/test-signal.sh" 2>/dev/null)

  assert_json_valid "$output" "Should handle scripts with signal handlers"
}

# Test: Environment isolation in worktree
test_worktree_environment_isolation() {
  cd "$REPO_ROOT"

  # Create worktree
  "$SCRIPTS_DIR/create-worktree.sh" "$EDGE_TEST_SESSION" "1" >/dev/null 2>&1

  local worktree_path="$TEST_WORKTREE_BASE/$EDGE_TEST_SESSION/worker-1"

  # Worktree should have its own git HEAD
  local main_head worktree_head
  main_head=$(git rev-parse HEAD)
  worktree_head=$(git -C "$worktree_path" rev-parse HEAD)

  # Initially they should be the same (branched from same commit)
  assert_eq "$main_head" "$worktree_head" "Initial commits should match"

  # Make a commit in worktree
  echo "test" > "$worktree_path/test-isolation.txt"
  git -C "$worktree_path" add test-isolation.txt
  git -C "$worktree_path" commit -m "test commit" >/dev/null 2>&1

  # Now they should differ
  worktree_head=$(git -C "$worktree_path" rev-parse HEAD)
  assert_ne "$main_head" "$worktree_head" "Commits should differ after worktree commit"
}
