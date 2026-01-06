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

  # Run the test
  TEST_OUTPUT=$(eval "$TEST_COMMAND" 2>&1) || true

  # Try to parse JSON output
  METRIC=$(echo "$TEST_OUTPUT" | grep -o '"metric_value"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$' || echo "")
  SUCCESS=$(echo "$TEST_OUTPUT" | grep -o '"success"[[:space:]]*:[[:space:]]*true' || echo "")

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
  else
    echo "Goal not yet achieved. Current: $METRIC, Target: $GOAL"
    # Update state file with current metric
    # (In a real implementation, this would update the YAML properly)
  fi

  # Always exit 0 to let Ralph Wiggum handle the loop continuation
  exit 0
}

main "$@"
