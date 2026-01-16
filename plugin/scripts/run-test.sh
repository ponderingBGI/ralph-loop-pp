#!/bin/bash
#
# Run verification test and extract metric
#
# Usage: run-test.sh <test_command> [working_directory] [timeout]
#
# Outputs JSON with:
#   - success: boolean
#   - metric_value: number (if applicable)
#   - error: string (if failed)
#

set -euo pipefail

# ============================================================================
# Dependency check
# ============================================================================
if ! command -v jq &>/dev/null; then
  echo '{"success": false, "error": "jq is required but not installed"}'
  exit 1
fi

# ============================================================================
# Safe test command validation and execution
# ============================================================================
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
    return 1
  fi

  # Check command starts with allowed prefix
  for prefix in "${ALLOWED_PREFIXES[@]}"; do
    if [[ "$cmd" == "$prefix"* ]]; then
      return 0
    fi
  done

  return 1
}

# Safe JSON output function using jq
json_output() {
  local success="$1"
  local error="${2:-}"
  local output="${3:-}"
  local metric="${4:-}"

  if [[ -n "$metric" ]]; then
    jq -n --argjson success "$success" --arg error "$error" --arg output "${output:0:500}" --argjson metric "$metric" \
      '{success: $success, error: (if $error == "" then null else $error end), output: (if $output == "" then null else $output end), metric_value: $metric}'
  else
    jq -n --argjson success "$success" --arg error "$error" --arg output "${output:0:500}" \
      '{success: $success, error: (if $error == "" then null else $error end), output: (if $output == "" then null else $output end)}'
  fi
}

TEST_COMMAND="${1:?Usage: run-test.sh <test_command> [working_directory] [timeout]}"
WORKING_DIR="${2:-.}"
TIMEOUT="${3:-300}"  # 5 minute default timeout

# Validate timeout is a positive integer
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]] || [[ "$TIMEOUT" -gt 3600 ]]; then
  json_output "false" "Invalid timeout: must be 1-3600 seconds"
  exit 1
fi

# Validate test command
if ! validate_test_command "$TEST_COMMAND"; then
  json_output "false" "Invalid test command format. Must start with: node, python, npm, npx, pnpm, bun, pytest, jest, or vitest"
  exit 1
fi

# Change to working directory
if ! cd "$WORKING_DIR" 2>/dev/null; then
  json_output "false" "Cannot access working directory: $WORKING_DIR"
  exit 1
fi

# Run test with timeout
echo "Running test: $TEST_COMMAND" >&2
echo "Working directory: $(pwd)" >&2
echo "Timeout: ${TIMEOUT}s" >&2

# Execute command safely (without eval or bash -c)
# shellcheck disable=SC2086
OUTPUT=$(timeout "$TIMEOUT" $TEST_COMMAND 2>&1) || {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]]; then
    json_output "false" "Test timed out after $TIMEOUT seconds" "$OUTPUT"
    exit 1
  else
    json_output "false" "Test failed with exit code $EXIT_CODE" "$OUTPUT"
    exit 1
  fi
}

# Check if output is valid JSON
if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  # Already valid JSON, output as-is
  echo "$OUTPUT"
else
  # Try to extract a number from the output
  METRIC=$(echo "$OUTPUT" | grep -oE '[0-9]+\.?[0-9]*' | tail -1 || echo "")

  if [[ -n "$METRIC" ]]; then
    # Use jq to safely construct JSON with proper escaping
    jq -n --argjson metric "$METRIC" --arg output "${OUTPUT:0:200}" \
      '{success: true, metric_value: $metric, raw_output: $output}'
  else
    # Use jq to safely escape the output
    jq -n --arg output "${OUTPUT:0:500}" \
      '{success: true, raw_output: $output}'
  fi
fi
