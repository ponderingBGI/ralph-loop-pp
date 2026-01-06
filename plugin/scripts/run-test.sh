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

TEST_COMMAND="${1:?Usage: run-test.sh <test_command> [working_directory] [timeout]}"
WORKING_DIR="${2:-.}"
TIMEOUT="${3:-300}"  # 5 minute default timeout

cd "$WORKING_DIR"

# Helper function to escape string for JSON (pure bash, no jq dependency)
json_escape() {
  local input="$1"
  local escaped=""
  local i char

  for (( i=0; i<${#input}; i++ )); do
    char="${input:$i:1}"
    case "$char" in
      '"')  escaped+='\"' ;;
      '\\') escaped+='\\\\' ;;
      $'\n') escaped+='\n' ;;
      $'\r') escaped+='\r' ;;
      $'\t') escaped+='\t' ;;
      *)
        # Check if it's a control character (ASCII 0-31)
        if [[ "$char" < $'\x20' ]]; then
          # Convert to unicode escape
          printf -v escaped '%s\\u%04x' "$escaped" "'$char"
        else
          escaped+="$char"
        fi
        ;;
    esac
  done
  printf '"%s"' "$escaped"
}

# Helper function to check if string is valid JSON
is_valid_json() {
  local input="$1"
  # Simple heuristic: starts with { or [ and ends with } or ]
  # and has balanced braces (very basic check)
  if [[ "$input" =~ ^\{.*\}$ ]] || [[ "$input" =~ ^\[.*\]$ ]]; then
    # Try to parse with python if available, otherwise accept it
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "import json; json.loads('''$input''')" 2>/dev/null && return 0
    elif command -v python >/dev/null 2>&1; then
      python -c "import json; json.loads('''$input''')" 2>/dev/null && return 0
    else
      # No python, accept anything that looks like JSON
      return 0
    fi
  fi
  return 1
}

# Run test with timeout
echo "Running test: $TEST_COMMAND" >&2
echo "Working directory: $(pwd)" >&2
echo "Timeout: ${TIMEOUT}s" >&2

OUTPUT=$(timeout "$TIMEOUT" bash -c "$TEST_COMMAND" 2>&1) || {
  EXIT_CODE=$?
  ESCAPED_OUTPUT=$(json_escape "${OUTPUT:0:500}")
  if [[ $EXIT_CODE -eq 124 ]]; then
    echo '{"success": false, "error": "Test timed out after '"$TIMEOUT"' seconds"}'
    exit 1
  else
    echo '{"success": false, "error": "Test failed with exit code '"$EXIT_CODE"'", "output": '"$ESCAPED_OUTPUT"'}'
    exit 1
  fi
}

# Check if output is valid JSON
if is_valid_json "$OUTPUT"; then
  # Already valid JSON, output as-is
  echo "$OUTPUT"
else
  # Try to extract a number from the output
  METRIC=$(echo "$OUTPUT" | grep -oE '[0-9]+\.?[0-9]*' | tail -1 || echo "")

  if [[ -n "$METRIC" ]]; then
    ESCAPED_OUTPUT=$(json_escape "${OUTPUT:0:200}")
    echo '{"success": true, "metric_value": '"$METRIC"', "raw_output": '"$ESCAPED_OUTPUT"'}'
  else
    ESCAPED_OUTPUT=$(json_escape "${OUTPUT:0:500}")
    echo '{"success": true, "raw_output": '"$ESCAPED_OUTPUT"'}'
  fi
fi
