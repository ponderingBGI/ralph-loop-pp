#!/bin/bash
#
# Ralph-Loop++ Self-Test Runner
#
# Runs all plugin self-tests and reports results.
#
# Usage: ./run-tests.sh [test-file]
#   If test-file is specified, only runs that test file.
#   Otherwise, runs all test files in order.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

# Test result tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test utilities available to all test files
export SCRIPT_DIR
export PLUGIN_DIR
export REPO_ROOT
export TEST_SESSION_ID="test-$$-$(date +%s)"
export TEST_WORKTREE_BASE="/var/tmp/ralph-plus-worktrees"

# Logging functions
log_info() {
  echo -e "${YELLOW}[INFO]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
}

# Test assertion functions
assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should be equal}"

  if [[ "$expected" == "$actual" ]]; then
    return 0
  else
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    return 1
  fi
}

assert_ne() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should not be equal}"

  if [[ "$expected" != "$actual" ]]; then
    return 0
  else
    echo "  Values are equal: $actual"
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Should contain substring}"

  if [[ "$haystack" == *"$needle"* ]]; then
    return 0
  else
    echo "  String: $haystack"
    echo "  Missing: $needle"
    return 1
  fi
}

assert_file_exists() {
  local file="$1"
  local message="${2:-File should exist}"

  if [[ -f "$file" ]]; then
    return 0
  else
    echo "  File not found: $file"
    return 1
  fi
}

assert_dir_exists() {
  local dir="$1"
  local message="${2:-Directory should exist}"

  if [[ -d "$dir" ]]; then
    return 0
  else
    echo "  Directory not found: $dir"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Exit code should match}"

  if [[ "$expected" -eq "$actual" ]]; then
    return 0
  else
    echo "  Expected exit code: $expected"
    echo "  Actual exit code:   $actual"
    return 1
  fi
}

# Helper to get JSON value using python or jq
_json_get() {
  local json="$1"
  local key="$2"
  local result

  if command -v jq >/dev/null 2>&1; then
    result=$(echo "$json" | jq -r ".$key" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    result=$(python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
v=d.get('$key', '')
# Convert Python bools to JSON-style lowercase
if v is True: print('true')
elif v is False: print('false')
elif v is None: print('null')
else: print(v)
" <<< "$json" 2>/dev/null)
  elif command -v python >/dev/null 2>&1; then
    result=$(python -c "
import json,sys
d=json.loads(sys.stdin.read())
v=d.get('$key', '')
if v is True: print 'true'
elif v is False: print 'false'
elif v is None: print 'null'
else: print v
" <<< "$json" 2>/dev/null)
  else
    # Fallback: grep-based extraction (basic)
    result=$(echo "$json" | grep -oP "\"$key\"\\s*:\\s*\"?\\K[^\",}]+" | head -1)
  fi
  echo "$result"
}

_json_valid() {
  local json="$1"

  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq . >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; json.loads(sys.stdin.read())" <<< "$json" 2>/dev/null
  elif command -v python >/dev/null 2>&1; then
    python -c "import json,sys; json.loads(sys.stdin.read())" <<< "$json" 2>/dev/null
  else
    # Basic check: starts with { and ends with }
    [[ "$json" =~ ^\{.*\}$ ]]
  fi
}

_json_has_key() {
  local json="$1"
  local key="$2"

  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -e ".$key" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; d=json.loads(sys.stdin.read()); exit(0 if '$key' in d else 1)" <<< "$json" 2>/dev/null
  elif command -v python >/dev/null 2>&1; then
    python -c "import json,sys; d=json.loads(sys.stdin.read()); exit(0 if '$key' in d else 1)" <<< "$json" 2>/dev/null
  else
    # Basic check: key exists in string
    [[ "$json" == *"\"$key\""* ]]
  fi
}

assert_json_valid() {
  local json="$1"
  local message="${2:-Should be valid JSON}"

  if _json_valid "$json"; then
    return 0
  else
    echo "  Invalid JSON: $json"
    return 1
  fi
}

assert_json_has_key() {
  local json="$1"
  local key="$2"
  local message="${3:-JSON should have key}"

  if _json_has_key "$json" "$key"; then
    return 0
  else
    echo "  Missing key '$key' in: $json"
    return 1
  fi
}

assert_json_value() {
  local json="$1"
  local key="$2"
  local expected="$3"
  local message="${4:-JSON value should match}"

  local actual
  actual=$(_json_get "$json" "$key")

  if [[ "$actual" == "$expected" ]]; then
    return 0
  else
    echo "  Key: $key"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    return 1
  fi
}

# Export assertion functions for test files
export -f assert_eq assert_ne assert_contains
export -f assert_file_exists assert_dir_exists
export -f assert_exit_code assert_json_valid
export -f assert_json_has_key assert_json_value
export -f _json_get _json_valid _json_has_key
export -f log_info log_pass log_fail

# Run a single test function
run_test() {
  local test_name="$1"
  local test_func="$2"

  TESTS_RUN=$((TESTS_RUN + 1))

  echo -n "  $test_name ... "

  # Run test in subshell to capture failures
  local output
  local exit_code
  output=$($test_func 2>&1) && exit_code=$? || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_pass ""
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    log_fail ""
    if [[ -n "$output" ]]; then
      echo "$output" | sed 's/^/    /'
    fi
  fi
}

# Run a test file
run_test_file() {
  local test_file="$1"
  local test_name
  test_name=$(basename "$test_file" .sh)

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Running: $test_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Source the test file to load test functions
  # shellcheck disable=SC1090
  source "$test_file"

  # Run setup if defined
  if declare -f setup >/dev/null; then
    log_info "Running setup..."
    setup
  fi

  # Find and run all test functions (functions starting with "test_")
  local test_funcs
  test_funcs=$(declare -F | awk '{print $3}' | grep "^test_" || true)

  for test_func in $test_funcs; do
    run_test "$test_func" "$test_func"
  done

  # Run teardown if defined
  if declare -f teardown >/dev/null; then
    log_info "Running teardown..."
    teardown
  fi

  # Unset test functions to avoid pollution
  for test_func in $test_funcs; do
    unset -f "$test_func"
  done
  unset -f setup teardown 2>/dev/null || true
}

# Main
main() {
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║           Ralph-Loop++ Self-Test Suite                           ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Plugin directory: $PLUGIN_DIR"
  echo "Test session ID:  $TEST_SESSION_ID"
  echo ""

  # Determine which tests to run
  local test_files=()

  if [[ $# -gt 0 ]]; then
    # Run specific test file
    test_files=("$1")
  else
    # Run all test files in order
    test_files=(
      "$SCRIPT_DIR/test-worktree.sh"
      "$SCRIPT_DIR/test-state-file.sh"
      "$SCRIPT_DIR/test-run-test.sh"
      "$SCRIPT_DIR/test-edge-cases.sh"
    )
  fi

  # Run tests
  for test_file in "${test_files[@]}"; do
    if [[ -f "$test_file" ]]; then
      run_test_file "$test_file"
    else
      log_fail "Test file not found: $test_file"
    fi
  done

  # Print summary
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║                         Test Summary                             ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Total tests:  $TESTS_RUN"
  echo -e "  Passed:       ${GREEN}$TESTS_PASSED${NC}"
  echo -e "  Failed:       ${RED}$TESTS_FAILED${NC}"

  if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for failed in "${FAILED_TESTS[@]}"; do
      echo -e "  ${RED}✗${NC} $failed"
    done
  fi

  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
  fi
}

main "$@"
