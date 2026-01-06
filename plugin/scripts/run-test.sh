#!/bin/bash
#
# Run verification test and extract metric
#
# Usage: run-test.sh <test_command> [working_directory]
#
# Outputs JSON with:
#   - success: boolean
#   - metric_value: number (if applicable)
#   - error: string (if failed)
#

set -euo pipefail

TEST_COMMAND="${1:?Usage: run-test.sh <test_command> [working_directory]}"
WORKING_DIR="${2:-.}"
TIMEOUT="${3:-300}"  # 5 minute default timeout

cd "$WORKING_DIR"

# Run test with timeout
echo "Running test: $TEST_COMMAND" >&2
echo "Working directory: $(pwd)" >&2
echo "Timeout: ${TIMEOUT}s" >&2

OUTPUT=$(timeout "$TIMEOUT" bash -c "$TEST_COMMAND" 2>&1) || {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]]; then
    echo '{"success": false, "error": "Test timed out after '"$TIMEOUT"' seconds"}'
    exit 1
  else
    echo '{"success": false, "error": "Test failed with exit code '"$EXIT_CODE"'", "output": "'"${OUTPUT:0:500}"'"}'
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
    echo '{"success": true, "metric_value": '"$METRIC"', "raw_output": "'"${OUTPUT:0:200}"'"}'
  else
    echo '{"success": true, "raw_output": "'"${OUTPUT:0:500}"'"}'
  fi
fi
