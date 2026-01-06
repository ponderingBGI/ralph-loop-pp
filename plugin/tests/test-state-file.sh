#!/bin/bash
#
# Tests for state file read/write operations
#
# Tests:
# - State file can be created with valid YAML frontmatter
# - State file can be read and parsed correctly
# - YAML parsing extracts correct values
# - State file updates preserve existing data
# - Multiple fields can be updated atomically
# - Invalid YAML is handled gracefully
# - Missing file is handled gracefully
#

# shellcheck source=./run-tests.sh
# Assertions and exports are loaded from run-tests.sh

STATE_DIR="$SCRIPT_DIR/fixtures"
TEST_STATE_FILE="$STATE_DIR/test-state.local.md"

setup() {
  # Create fixtures directory
  mkdir -p "$STATE_DIR"

  # Clean up any existing test state file
  rm -f "$TEST_STATE_FILE"
}

teardown() {
  # Clean up test state file
  rm -f "$TEST_STATE_FILE"
}

# Helper: Create a valid state file
create_test_state_file() {
  cat > "$TEST_STATE_FILE" << 'EOF'
---
active: true
session_id: "rp-1704567890123"
started_at: "2024-01-06T10:00:00Z"
updated_at: "2024-01-06T10:30:00Z"
task: "Reduce API response time by 50%"
target: "API response time"
metric: "p95 latency"
goal: 50
goal_unit: "ms"
direction: "decrease"
phase: "worker_exploration"
test_file: "tests/benchmarks/api_latency.js"
test_command: "node tests/benchmarks/api_latency.js"
baseline_metric: 120
best_metric: 65
current_metric: 72
last_error: null
recovery_attempts: 0
---

# Ralph-Loop++ Session

This is the session documentation section.
EOF
}

# Helper: Parse YAML frontmatter (mirrors hook implementation)
parse_yaml() {
  local file="$1"
  local key="$2"
  grep "^${key}:" "$file" | head -1 | sed "s/^${key}: *//" | sed 's/"//g'
}

# Test: Can create a valid state file
test_create_state_file() {
  create_test_state_file

  assert_file_exists "$TEST_STATE_FILE" "State file should be created"
}

# Test: YAML frontmatter has correct format
test_yaml_frontmatter_format() {
  create_test_state_file

  # Check for opening and closing ---
  local first_line
  local has_closing
  first_line=$(head -1 "$TEST_STATE_FILE")
  has_closing=$(grep -n "^---$" "$TEST_STATE_FILE" | wc -l)

  assert_eq "---" "$first_line" "First line should be ---"
  if [[ "$has_closing" -lt 2 ]]; then
    echo "  Missing closing ---"
    return 1
  fi
  return 0
}

# Test: Can parse active field
test_parse_active_field() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "active")

  assert_eq "true" "$value" "Active field should be true"
}

# Test: Can parse session_id field
test_parse_session_id() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "session_id")

  assert_eq "rp-1704567890123" "$value" "Session ID should match"
}

# Test: Can parse numeric goal field
test_parse_numeric_goal() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "goal")

  assert_eq "50" "$value" "Goal should be 50"
}

# Test: Can parse direction field
test_parse_direction() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "direction")

  assert_eq "decrease" "$value" "Direction should be decrease"
}

# Test: Can parse phase field
test_parse_phase() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "phase")

  assert_eq "worker_exploration" "$value" "Phase should be worker_exploration"
}

# Test: Can parse test_command field
test_parse_test_command() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "test_command")

  assert_eq "node tests/benchmarks/api_latency.js" "$value" "Test command should match"
}

# Test: Handles missing key gracefully
test_parse_missing_key() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "nonexistent_key")

  assert_eq "" "$value" "Missing key should return empty string"
}

# Test: Handles null values
test_parse_null_value() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "last_error")

  assert_eq "null" "$value" "Null value should be 'null'"
}

# Test: State file can be updated via sed
test_update_state_via_sed() {
  create_test_state_file

  # Update phase
  sed -i 's/^phase: .*/phase: evaluation/' "$TEST_STATE_FILE"

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "phase")

  assert_eq "evaluation" "$value" "Phase should be updated to evaluation"
}

# Test: Update preserves other fields
test_update_preserves_fields() {
  create_test_state_file

  # Update phase
  sed -i 's/^phase: .*/phase: complete/' "$TEST_STATE_FILE"

  # Check other fields are preserved
  local session
  local goal
  local direction

  session=$(parse_yaml "$TEST_STATE_FILE" "session_id")
  goal=$(parse_yaml "$TEST_STATE_FILE" "goal")
  direction=$(parse_yaml "$TEST_STATE_FILE" "direction")

  assert_eq "rp-1704567890123" "$session" "Session ID should be preserved"
  assert_eq "50" "$goal" "Goal should be preserved"
  assert_eq "decrease" "$direction" "Direction should be preserved"
}

# Test: Update numeric value
test_update_numeric_value() {
  create_test_state_file

  # Update best_metric
  sed -i 's/^best_metric: .*/best_metric: 45/' "$TEST_STATE_FILE"

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "best_metric")

  assert_eq "45" "$value" "Best metric should be updated to 45"
}

# Test: Update timestamp value
test_update_timestamp() {
  create_test_state_file

  local new_time="2024-01-06T12:00:00Z"
  sed -i "s/^updated_at: .*/updated_at: \"$new_time\"/" "$TEST_STATE_FILE"

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "updated_at")

  assert_eq "$new_time" "$value" "Timestamp should be updated"
}

# Test: State file with quoted strings
test_quoted_strings() {
  create_test_state_file

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "task")

  assert_eq "Reduce API response time by 50%" "$value" "Quoted string should be parsed correctly"
}

# Test: Handle empty state file gracefully
test_empty_file() {
  # Create a truly empty file (overwrite any existing content)
  : > "$TEST_STATE_FILE"

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "active")

  assert_eq "" "$value" "Empty file should return empty string"
}

# Test: Handle malformed YAML
test_malformed_yaml() {
  cat > "$TEST_STATE_FILE" << 'EOF'
---
active true
session_id
: malformed
---
EOF

  # Parsing should not crash
  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "active") || true

  # Should either return empty or the malformed value, but not crash
  return 0
}

# Test: Multiple consecutive parses
test_multiple_parses() {
  create_test_state_file

  # Parse multiple fields in sequence
  local active session phase goal

  active=$(parse_yaml "$TEST_STATE_FILE" "active")
  session=$(parse_yaml "$TEST_STATE_FILE" "session_id")
  phase=$(parse_yaml "$TEST_STATE_FILE" "phase")
  goal=$(parse_yaml "$TEST_STATE_FILE" "goal")

  assert_eq "true" "$active"
  assert_eq "rp-1704567890123" "$session"
  assert_eq "worker_exploration" "$phase"
  assert_eq "50" "$goal"
}

# Test: State file with special characters in task
test_special_characters() {
  cat > "$TEST_STATE_FILE" << 'EOF'
---
active: true
task: "Optimize query: SELECT * FROM users WHERE id > 100"
---
EOF

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "task")

  assert_contains "$value" "SELECT" "Special characters should be handled"
}

# Test: Parse value with spaces
test_value_with_spaces() {
  cat > "$TEST_STATE_FILE" << 'EOF'
---
test_command: node tests/benchmarks/api_latency.js --verbose --timeout 30
---
EOF

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "test_command")

  assert_eq "node tests/benchmarks/api_latency.js --verbose --timeout 30" "$value" "Value with spaces should be parsed"
}

# Test: Concurrent reads (simulated)
test_concurrent_reads() {
  create_test_state_file

  # Simulate concurrent reads by running multiple in quick succession
  local results=()
  for i in {1..5}; do
    results+=("$(parse_yaml "$TEST_STATE_FILE" "session_id")")
  done

  # All results should be the same
  for result in "${results[@]}"; do
    assert_eq "rp-1704567890123" "$result" "Concurrent reads should return same value"
  done
}

# Test: File permissions
test_file_permissions() {
  create_test_state_file

  # File should be readable
  if [[ -r "$TEST_STATE_FILE" ]]; then
    return 0
  else
    echo "  State file is not readable"
    return 1
  fi
}

# Test: Write and read cycle
test_write_read_cycle() {
  # Create new state file from scratch
  local new_session="rp-$(date +%s)"

  cat > "$TEST_STATE_FILE" << EOF
---
active: true
session_id: "$new_session"
phase: initialization
---
EOF

  local value
  value=$(parse_yaml "$TEST_STATE_FILE" "session_id")

  assert_eq "$new_session" "$value" "Written session ID should be readable"
}
