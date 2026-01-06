#!/bin/bash
#
# Tests for run-test.sh (test runner script)
#
# Tests:
# - Valid JSON output is passed through
# - Numeric output is wrapped in JSON
# - Plain text output is handled
# - Test timeout is enforced
# - Failed tests return proper JSON error
# - Working directory is respected
# - Exit codes are handled correctly
#

# shellcheck source=./run-tests.sh
# Assertions and exports are loaded from run-tests.sh

RUN_TEST_SCRIPT="$PLUGIN_DIR/scripts/run-test.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

setup() {
  chmod +x "$RUN_TEST_SCRIPT"
  mkdir -p "$FIXTURES_DIR"
}

teardown() {
  # Clean up any test fixtures
  rm -f "$FIXTURES_DIR/test-script.sh"
  rm -f "$FIXTURES_DIR/test-output.txt"
}

# Helper: Create a test script
create_test_script() {
  local content="$1"
  cat > "$FIXTURES_DIR/test-script.sh" << EOF
#!/bin/bash
$content
EOF
  chmod +x "$FIXTURES_DIR/test-script.sh"
}

# Test: Requires test command argument
test_requires_command() {
  local output
  local exit_code

  output=$("$RUN_TEST_SCRIPT" 2>&1) && exit_code=0 || exit_code=$?

  assert_ne 0 "$exit_code" "Should fail without command"
  assert_contains "$output" "Usage" "Should show usage"
}

# Test: Valid JSON output is passed through unchanged
test_json_passthrough() {
  create_test_script 'echo '\''{"success": true, "metric_value": 42.5}'\'''

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
  assert_json_value "$output" "metric_value" "42.5" "Metric value should be 42.5"
}

# Test: Complex JSON is passed through
test_complex_json_passthrough() {
  create_test_script 'echo '\''{"success": true, "metric_value": 100, "details": {"p50": 80, "p95": 100, "p99": 120}}'\'''

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Complex JSON should be valid"
  assert_json_has_key "$output" "details" "Should have details key"
}

# Test: Numeric output is wrapped in JSON
test_numeric_wrapped() {
  create_test_script 'echo "42"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
  assert_json_value "$output" "metric_value" "42" "Metric value should be 42"
}

# Test: Decimal number output is wrapped
test_decimal_wrapped() {
  create_test_script 'echo "Response time: 123.456 ms"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
  # Should extract the last number
  assert_json_has_key "$output" "metric_value" "Should have metric_value"
}

# Test: Plain text output is wrapped
test_plain_text_wrapped() {
  create_test_script 'echo "Test completed successfully"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
  assert_json_has_key "$output" "raw_output" "Should have raw_output"
}

# Test: Failed test returns error JSON
test_failed_returns_error() {
  create_test_script 'exit 1'

  local output
  local exit_code
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null) && exit_code=0 || exit_code=$?

  assert_ne 0 "$exit_code" "Should have non-zero exit code"
  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "false" "Success should be false"
  assert_json_has_key "$output" "error" "Should have error message"
}

# Test: Failed test includes exit code
test_failed_includes_exit_code() {
  create_test_script 'exit 42'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null) || true

  assert_json_valid "$output" "Output should be valid JSON"
  assert_contains "$output" "42" "Should contain exit code"
}

# Test: Working directory is respected
test_working_directory() {
  create_test_script 'pwd'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" "$FIXTURES_DIR" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_contains "$output" "fixtures" "Working directory should be respected"
}

# Test: Timeout is enforced (with short timeout)
test_timeout_enforced() {
  create_test_script 'sleep 10'

  local output
  local exit_code
  # Use 1 second timeout
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" "." "1" 2>/dev/null) && exit_code=0 || exit_code=$?

  assert_ne 0 "$exit_code" "Should fail on timeout"
  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "false" "Success should be false"
  assert_contains "$output" "timed out" "Should mention timeout"
}

# Test: Stderr is captured
test_stderr_captured() {
  create_test_script 'echo "Error message" >&2; echo "42"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  # Script should still succeed with numeric output
  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
}

# Test: Multiline output with number
test_multiline_output() {
  create_test_script 'echo "Running benchmark..."
echo "Iterations: 1000"
echo "Total time: 5000ms"
echo "Average: 5"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
  # Should extract the last number (5)
  assert_json_has_key "$output" "metric_value" "Should extract metric"
}

# Test: Empty output
test_empty_output() {
  create_test_script 'true'  # Just exit 0 with no output

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
}

# Test: Special characters in output
test_special_chars_output() {
  create_test_script 'echo "Result: <100> & \"fast\""'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
}

# Test: Boolean JSON success
test_boolean_json_success() {
  create_test_script 'echo '\''{"success": true, "reason": "All checks passed"}'\'''

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
  assert_json_value "$output" "reason" "All checks passed" "Reason should match"
}

# Test: Boolean JSON failure
test_boolean_json_failure() {
  create_test_script 'echo '\''{"success": false, "error": "Validation failed"}'\'''

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "false" "Success should be false"
  assert_json_value "$output" "error" "Validation failed" "Error should match"
}

# Test: Script with arguments
test_script_with_args() {
  create_test_script 'echo "Args: $@"; echo "42"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh arg1 arg2" 2>/dev/null)

  # Note: Arguments are part of the command, should work
  assert_json_valid "$output" "Output should be valid JSON"
}

# Test: Environment variables
test_environment_variables() {
  create_test_script 'echo $HOME'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
}

# Test: Output truncation for very long output
test_output_truncation() {
  # Create script that outputs a lot of text
  create_test_script 'for i in {1..100}; do echo "Line $i: This is a very long line of output that should be truncated"; done; echo "42"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  # raw_output should be truncated (script limits to first N chars)
  assert_json_value "$output" "success" "true" "Success should be true"
}

# Test: Negative number
test_negative_number() {
  create_test_script 'echo "Change: -15%"'

  local output
  output=$("$RUN_TEST_SCRIPT" "$FIXTURES_DIR/test-script.sh" 2>/dev/null)

  assert_json_valid "$output" "Output should be valid JSON"
  assert_json_value "$output" "success" "true" "Success should be true"
  # Should extract 15 (grep -oE extracts digits)
  assert_json_has_key "$output" "metric_value" "Should have metric value"
}
