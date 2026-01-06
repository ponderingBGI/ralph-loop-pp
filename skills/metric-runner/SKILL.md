# Metric Runner Skill

Runs verification tests and extracts metrics for ralph-loop++.

## Purpose

Execute the verification test created by the Test Architect and parse the results into a usable format for decision-making.

## Running a Test

```bash
TEST_COMMAND="$1"
WORKING_DIR="$2"

cd "$WORKING_DIR"

# Run test and capture output
OUTPUT=$(eval "$TEST_COMMAND" 2>&1)
EXIT_CODE=$?

# Output both the JSON result and exit code
echo "$OUTPUT"
exit $EXIT_CODE
```

## Parsing Results

### Numeric Metric
```javascript
const output = `{"success": true, "metric_value": 45.2, "unit": "ms"}`;
const result = JSON.parse(output);

if (result.success && result.metric_value !== undefined) {
  console.log(`Metric: ${result.metric_value} ${result.unit || ''}`);
}
```

### Boolean Success
```javascript
const output = `{"success": true, "reason": "All tests passed"}`;
const result = JSON.parse(output);

if (result.success !== undefined) {
  console.log(`Success: ${result.success}`);
  if (result.reason) console.log(`Reason: ${result.reason}`);
}
```

## Expected Output Formats

### Valid Formats
```json
{"success": true, "metric_value": 42, "unit": "ms"}
{"success": true, "metric_name": "latency", "metric_value": 42}
{"success": false, "error": "Connection refused"}
{"success": true, "reason": "All 10 runs passed"}
{"success": true}
```

### Invalid Formats (Handle Gracefully)
```
# Plain text output - treat as failure
Error: something went wrong

# Non-JSON - treat as failure
42

# Missing success field - infer from metric_value
{"metric_value": 42}
```

## Comparison Logic

### Numeric Metrics

```javascript
function checkNumericGoal(current, target, direction) {
  if (direction === 'decrease') {
    return current <= target;
  } else if (direction === 'increase') {
    return current >= target;
  }
  return false;
}

// Example
const achieved = checkNumericGoal(45, 50, 'decrease');  // true
```

### Boolean Metrics

```javascript
function checkBooleanGoal(result) {
  return result.success === true;
}
```

## Progress Tracking

After each test run, update the state file:

```yaml
# Append to metrics_history
metrics_history:
  - timestamp: "2024-01-06T10:30:00Z"
    worker: 1
    iteration: 5
    metric_value: 85
    goal_achieved: false
```

## Handling Test Failures

### Test Crashes
```bash
if [[ $EXIT_CODE -ne 0 ]]; then
  echo '{"success": false, "error": "Test crashed with exit code '$EXIT_CODE'"}'
fi
```

### Timeout
```bash
timeout 300 $TEST_COMMAND || echo '{"success": false, "error": "Test timed out after 5 minutes"}'
```

### Invalid JSON
```javascript
try {
  const result = JSON.parse(output);
} catch (e) {
  return {
    success: false,
    error: `Invalid JSON output: ${output.substring(0, 100)}`
  };
}
```

## Baseline Measurement

When establishing baseline:

```javascript
// Run test multiple times for stability
const runs = 3;
const results = [];

for (let i = 0; i < runs; i++) {
  const result = runTest(testCommand);
  results.push(result.metric_value);
}

// Use median for baseline
results.sort((a, b) => a - b);
const baseline = results[Math.floor(runs / 2)];

console.log(`Baseline established: ${baseline}`);
```

## Integration with Ralph Loop

The worker stop hook uses this skill to:
1. Run the verification test after each iteration
2. Parse the metric value
3. Compare against target
4. Decide whether to continue or signal completion

```bash
# In stop hook
RESULT=$(run-metric-test "$TEST_COMMAND" "$WORKTREE_PATH")
METRIC=$(echo "$RESULT" | jq -r '.metric_value // empty')

if [[ -n "$METRIC" ]] && (( $(echo "$METRIC <= $TARGET" | bc -l) )); then
  echo "<promise>GOAL ACHIEVED: $METRIC</promise>"
fi
```
