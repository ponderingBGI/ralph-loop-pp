#!/bin/bash
#
# Ralph-Loop++ Worker Stop Hook
#
# This hook runs when a worker attempts to exit.
# It runs the verification test and checks if the goal is achieved.
#
# Integration with Ralph Wiggum:
# - This hook runs BEFORE Ralph Wiggum's stop hook
# - If goal is achieved, we signal completion
# - Ralph Wiggum then decides whether to continue the loop
#

set -euo pipefail

# ============================================================================
# Dependency checks
# ============================================================================
check_dependencies() {
  local missing=()
  command -v bc &>/dev/null || missing+=("bc")
  command -v jq &>/dev/null || missing+=("jq")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing required dependencies: ${missing[*]}" >&2
    echo "Install with: apt-get install ${missing[*]}" >&2
    exit 1
  fi
}

check_dependencies

# ============================================================================
# Cross-platform compatibility helpers
# ============================================================================
# Portable sed in-place edit (macOS requires empty string for -i)
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Portable ISO 8601 timestamp (macOS date doesn't support -Iseconds)
iso_timestamp() {
  if date -Iseconds &>/dev/null 2>&1; then
    date -Iseconds
  else
    # macOS fallback
    date -u +"%Y-%m-%dT%H:%M:%S%z"
  fi
}

# Portable file locking (flock not available on macOS by default)
acquire_lock() {
  local lock_file="$1"
  local timeout="${2:-10}"

  if command -v flock &>/dev/null; then
    # Linux: use flock
    exec 200>"$lock_file"
    flock -x -w "$timeout" 200
  else
    # macOS fallback: use mkdir as lock (atomic operation)
    local lock_dir="${lock_file}.d"
    local start_time=$(date +%s)
    while ! mkdir "$lock_dir" 2>/dev/null; do
      if (( $(date +%s) - start_time > timeout )); then
        return 1
      fi
      sleep 0.1
    done
    # Store our PID so we can clean up
    echo $$ > "$lock_dir/pid"
  fi
}

release_lock() {
  local lock_file="$1"
  local lock_dir="${lock_file}.d"

  if [[ -d "$lock_dir" ]]; then
    rm -rf "$lock_dir"
  fi
}

# ============================================================================
# Safe test command execution (prevents command injection)
# ============================================================================
# Allowed test command patterns - commands must start with one of these
ALLOWED_PREFIXES=(
  "node "
  "python "
  "python3 "
  "npm "
  "npx "
  "pnpm "
  "bun "
  "pytest "
  "jest "
  "vitest "
)

validate_test_command() {
  local cmd="$1"

  # Check for dangerous patterns
  if [[ "$cmd" =~ [\;\|\&\`\$\(] ]]; then
    echo "Error: Test command contains disallowed characters (;|&\`\$())" >&2
    return 1
  fi

  # Check command starts with allowed prefix
  for prefix in "${ALLOWED_PREFIXES[@]}"; do
    if [[ "$cmd" == "$prefix"* ]]; then
      return 0
    fi
  done

  echo "Error: Test command must start with one of: ${ALLOWED_PREFIXES[*]}" >&2
  return 1
}

run_test_safely() {
  local cmd="$1"
  local timeout_secs="${2:-300}"

  if ! validate_test_command "$cmd"; then
    echo '{"success": false, "error": "Invalid test command format"}'
    return 1
  fi

  # Run without eval - directly execute the command
  # shellcheck disable=SC2086
  timeout "$timeout_secs" $cmd 2>&1
}

# Get the state file path (could be in worktree or main repo)
find_state_file() {
  # Check if we're in a worktree
  if [[ -f ".claude/ralph-plus.local.md" ]]; then
    echo ".claude/ralph-plus.local.md"
  elif [[ -f "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/ralph-plus.local.md" ]]; then
    echo "$(git rev-parse --show-toplevel)/.claude/ralph-plus.local.md"
  else
    echo ""
  fi
}

# Parse YAML frontmatter from state file
parse_yaml() {
  local file="$1"
  local key="$2"
  # Simple YAML parsing - get value after "key: "
  grep "^${key}:" "$file" | head -1 | sed "s/^${key}: *//" | sed 's/"//g'
}

# Main hook logic
main() {
  STATE_FILE=$(find_state_file)

  if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
    # No active session, let normal exit proceed
    exit 0
  fi

  # Check if this is an active worker session
  ACTIVE=$(parse_yaml "$STATE_FILE" "active")
  PHASE=$(parse_yaml "$STATE_FILE" "phase")

  if [[ "$ACTIVE" != "true" || "$PHASE" != "worker_exploration" ]]; then
    # Not in worker exploration phase, let normal exit proceed
    exit 0
  fi

  # Get test configuration
  TEST_COMMAND=$(parse_yaml "$STATE_FILE" "test_command")
  GOAL=$(parse_yaml "$STATE_FILE" "goal")
  DIRECTION=$(parse_yaml "$STATE_FILE" "direction")

  if [[ -z "$TEST_COMMAND" || -z "$GOAL" ]]; then
    echo "Warning: Missing test configuration in state file"
    exit 0
  fi

  echo "=== Ralph-Loop++ Stop Hook ==="
  echo "Running verification test..."

  # Run the test safely (no eval)
  TEST_OUTPUT=$(run_test_safely "$TEST_COMMAND" 300) || true

  # Try to parse JSON output using jq for safety
  METRIC=""
  SUCCESS=""
  if echo "$TEST_OUTPUT" | jq . &>/dev/null; then
    METRIC=$(echo "$TEST_OUTPUT" | jq -r '.metric_value // empty')
    SUCCESS=$(echo "$TEST_OUTPUT" | jq -r 'if .success == true then "true" else empty end')
  fi

  if [[ -z "$METRIC" && -z "$SUCCESS" ]]; then
    echo "Could not parse test output"
    echo "Output: ${TEST_OUTPUT:0:200}"
    exit 0
  fi

  echo "Metric: $METRIC"
  echo "Goal: $GOAL ($DIRECTION)"

  # Check if goal is achieved
  ACHIEVED=false
  if [[ -n "$SUCCESS" ]]; then
    # Boolean success
    ACHIEVED=true
  elif [[ -n "$METRIC" ]]; then
    # Numeric comparison
    if [[ "$DIRECTION" == "decrease" ]]; then
      if (( $(echo "$METRIC <= $GOAL" | bc -l) )); then
        ACHIEVED=true
      fi
    else
      if (( $(echo "$METRIC >= $GOAL" | bc -l) )); then
        ACHIEVED=true
      fi
    fi
  fi

  if [[ "$ACHIEVED" == "true" ]]; then
    echo "GOAL ACHIEVED!"
    # This will be picked up by Ralph Wiggum to stop the loop
    echo "<promise>GOAL ACHIEVED: $METRIC</promise>"
    # Update state file to record achievement
    update_state_metric "$STATE_FILE" "$METRIC" "true"
  else
    echo "Goal not yet achieved. Current: $METRIC, Target: $GOAL"
    # Update state file with current metric
    update_state_metric "$STATE_FILE" "$METRIC" "false"
  fi

  # Always exit 0 to let Ralph Wiggum handle the loop continuation
  exit 0
}

# ============================================================================
# State file update with locking (prevents race conditions)
# ============================================================================
update_state_metric() {
  local state_file="$1"
  local metric="$2"
  local achieved="${3:-false}"
  local lock_file="${state_file}.lock"

  # Acquire exclusive lock with timeout (cross-platform)
  if ! acquire_lock "$lock_file" 10; then
    echo "Warning: Could not acquire lock on state file" >&2
    return 1
  fi

  # Ensure lock is released on exit
  trap 'release_lock "$lock_file"' EXIT

  # Update state file using portable sed
  local timestamp
  timestamp=$(iso_timestamp)

  # Update current_metric if line exists
  if grep -q "^current_metric:" "$state_file" 2>/dev/null; then
    sed_inplace "s/^current_metric:.*/current_metric: $metric/" "$state_file"
  fi

  # Update updated_at if line exists
  if grep -q "^updated_at:" "$state_file" 2>/dev/null; then
    sed_inplace "s/^updated_at:.*/updated_at: \"$timestamp\"/" "$state_file"
  fi

  # Update best_metric if this is better (respects direction from state file)
  local current_best direction is_better
  current_best=$(grep "^best_metric:" "$state_file" 2>/dev/null | sed 's/^best_metric: *//' || echo "")
  direction=$(grep "^direction:" "$state_file" 2>/dev/null | sed 's/^direction: *//' | sed 's/"//g' || echo "decrease")
  if [[ -n "$current_best" && -n "$metric" ]]; then
    # Check if new metric is better based on direction
    is_better=0
    if [[ "$direction" == "increase" ]]; then
      (( $(echo "$metric > $current_best" | bc -l) )) && is_better=1
    else
      (( $(echo "$metric < $current_best" | bc -l) )) && is_better=1
    fi
    if [[ "$is_better" -eq 1 ]]; then
      sed_inplace "s/^best_metric:.*/best_metric: $metric/" "$state_file"
    fi
  fi

  # Release lock
  release_lock "$lock_file"
  trap - EXIT
}

main "$@"
