# Progress Tracker Skill

Manages state persistence and progress tracking for ralph-loop++.

## State File Location

`.claude/ralph-plus.local.md`

## State File Format

```yaml
---
# Session metadata
active: true
session_id: "rp-1704567890123"
started_at: "2024-01-06T10:00:00Z"
updated_at: "2024-01-06T10:30:00Z"

# User's original request
task: "Reduce API response time for /users endpoint to under 50ms"

# Parsed goals
target: "API response time"
metric: "p95 latency"
goal: 50
goal_unit: "ms"
direction: "decrease"

# Current phase
phase: "worker_exploration"
# Phases: initialization | test_creation | worker_exploration | evaluation | integration | cleanup | complete | cancelled | failed

# Test information
test_file: "tests/benchmarks/api_latency.js"
test_command: "node tests/benchmarks/api_latency.js"

# Metrics
baseline_metric: 120
best_metric: 65
current_metric: 72

# Worker tracking
workers:
  - id: 1
    worktree: "/var/tmp/ralph-plus-worktrees/rp-123/worker-1"
    branch: "ralph-plus/rp-123/worker-1"
    status: "running"
    iterations: 12
    best_metric: 65
    last_metric: 72
    approach: "Connection pooling + query optimization"
  - id: 2
    worktree: "/var/tmp/ralph-plus-worktrees/rp-123/worker-2"
    branch: "ralph-plus/rp-123/worker-2"
    status: "complete"
    iterations: 20
    best_metric: 78
    last_metric: 78
    approach: "Caching layer"

# Evaluation results
evaluations:
  - worker: 1
    decision: "accept"
    score: 4.2
    notes: "Clean implementation, good performance"

# Error tracking
last_error: null
recovery_attempts: 0

# Metrics history (recent entries)
metrics_history:
  - timestamp: "2024-01-06T10:05:00Z"
    worker: 1
    iteration: 1
    metric: 118
  - timestamp: "2024-01-06T10:10:00Z"
    worker: 1
    iteration: 5
    metric: 95
---

# Optimization Session: rp-1704567890123

## Original Request
Reduce API response time for /users endpoint to under 50ms

## Current Status
Phase: worker_exploration
Best so far: 65ms (Worker 1, iteration 12)
Target: 50ms

## Progress Log

### 10:00 - Session started
- Parsed request: reduce latency to under 50ms
- Created session rp-1704567890123

### 10:02 - Test created
- File: tests/benchmarks/api_latency.js
- Baseline: 120ms

### 10:05 - Workers spawned
- Worker 1: Connection pooling approach
- Worker 2: Caching approach

### 10:30 - Progress update
- Worker 1: 65ms (iteration 12) - close to target!
- Worker 2: 78ms (iteration 20) - max iterations reached
```

## State Operations

### Initialize Session

```javascript
const state = {
  active: true,
  session_id: `rp-${Date.now()}`,
  started_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  task: userRequest,
  phase: 'initialization',
  workers: [],
  metrics_history: []
};

writeStateFile(state);
```

### Update Phase

```javascript
function updatePhase(newPhase, notes) {
  const state = readStateFile();
  state.phase = newPhase;
  state.updated_at = new Date().toISOString();

  // Append to progress log
  appendToLog(state, `Phase changed to: ${newPhase}`, notes);

  writeStateFile(state);
}
```

### Record Metric

```javascript
function recordMetric(workerId, iteration, metric) {
  const state = readStateFile();

  // Update worker
  const worker = state.workers.find(w => w.id === workerId);
  worker.last_metric = metric;
  worker.iterations = iteration;
  if (metric < worker.best_metric || !worker.best_metric) {
    worker.best_metric = metric;
  }

  // Update global best
  if (metric < state.best_metric || !state.best_metric) {
    state.best_metric = metric;
  }

  // Add to history (keep last 50 entries)
  state.metrics_history.push({
    timestamp: new Date().toISOString(),
    worker: workerId,
    iteration,
    metric
  });
  if (state.metrics_history.length > 50) {
    state.metrics_history = state.metrics_history.slice(-50);
  }

  state.updated_at = new Date().toISOString();
  writeStateFile(state);
}
```

### Mark Worker Complete

```javascript
function markWorkerComplete(workerId, finalMetric, approach) {
  const state = readStateFile();

  const worker = state.workers.find(w => w.id === workerId);
  worker.status = 'complete';
  worker.last_metric = finalMetric;
  worker.approach = approach;

  state.updated_at = new Date().toISOString();
  writeStateFile(state);
}
```

### Session Recovery

```javascript
function recoverSession() {
  const state = readStateFile();

  if (!state || !state.active) {
    return null;
  }

  // Check for orphaned workers
  for (const worker of state.workers) {
    if (worker.status === 'running') {
      // Check if worktree still exists
      if (!fs.existsSync(worker.worktree)) {
        worker.status = 'crashed';
      }
    }
  }

  state.recovery_attempts = (state.recovery_attempts || 0) + 1;
  state.updated_at = new Date().toISOString();
  writeStateFile(state);

  return state;
}
```

## State Queries

### Check if Goal Achieved

```javascript
function isGoalAchieved(state) {
  if (state.direction === 'decrease') {
    return state.best_metric <= state.goal;
  } else {
    return state.best_metric >= state.goal;
  }
}
```

### Get Best Worker

```javascript
function getBestWorker(state) {
  return state.workers.reduce((best, worker) => {
    if (!best) return worker;
    if (state.direction === 'decrease') {
      return worker.best_metric < best.best_metric ? worker : best;
    } else {
      return worker.best_metric > best.best_metric ? worker : best;
    }
  }, null);
}
```

## Error Handling

### Record Error

```javascript
function recordError(error) {
  const state = readStateFile();
  state.last_error = {
    message: error.message,
    timestamp: new Date().toISOString()
  };
  state.updated_at = new Date().toISOString();
  writeStateFile(state);
}
```

### Clear Error

```javascript
function clearError() {
  const state = readStateFile();
  state.last_error = null;
  state.updated_at = new Date().toISOString();
  writeStateFile(state);
}
```

## Cleanup

### Complete Session

```javascript
function completeSession(success, summary) {
  const state = readStateFile();
  state.active = false;
  state.phase = success ? 'complete' : 'failed';
  state.completed_at = new Date().toISOString();
  state.summary = summary;
  writeStateFile(state);
}
```

### Archive Session

After completion, optionally move state file:
```bash
mv .claude/ralph-plus.local.md .claude/ralph-plus-archive/rp-{session_id}.md
```
