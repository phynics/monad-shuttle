# SHUT-021 State Machines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement explicit, validated transitions for server, repository, and shard states, including integration blocking behavior.

**Architecture:** Add an isolated runtime state machine actor that owns current server/repository/shard states and enforces transition maps. Return structured transition errors for invalid moves and for shard integration attempts while repository state is `blocked`.

**Tech Stack:** Swift 6, actor isolation, XCTest

---

### Task 1: Add State Machine Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleStateMachineTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- valid server transitions
- invalid server transition with structured error
- valid repository transitions
- invalid repository transition with structured error
- valid shard transitions
- blocked repository preventing shard integration

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleStateMachineTests`
Expected: FAIL because the state machine types do not exist yet.

### Task 2: Implement Runtime State Machine

**Files:**
- Create: `Sources/ShuttleServer/Runtime/ShuttleStateMachine.swift`

- [ ] **Step 1: Add repository and shard state enums**

```swift
public enum ShuttleRepositoryState { case open, refreshing, integrating, blocked }
public enum ShuttleShardState { case queued, running, needsInput, integrating, done, failed, abandoned }
```

- [ ] **Step 2: Add structured transition error and entity metadata**

```swift
public enum ShuttleStateTransitionError: Error, Equatable {
    case invalidTransition(entity: ShuttleStateMachineEntity, from: String, to: String, reason: String)
}
```

- [ ] **Step 3: Add actor with validated transition methods**

Methods:
- `transitionServer(to:)`
- `transitionRepository(to:)`
- `transitionShard(id:to:)`
- `shardState(id:)`

Rules:
- enforce allowed transition maps
- reject `transitionShard(..., .integrating)` when repository is `.blocked` with reason `repository_blocked`

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-05-29-shut-021-state-machines.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleStateMachineTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/Runtime/ShuttleStateMachine.swift Tests/ShuttleServerTests/ShuttleStateMachineTests.swift docs/superpowers/plans/2026-05-29-shut-021-state-machines.md
git commit -m "feat: add Shuttle runtime state machine"
```

## Self-Review

- Spec coverage: all required states and blocked integration behavior are encoded and tested.
- Placeholder scan: no deferred TODOs.
- Type consistency: state names and error reasons are stable for downstream API and persistence layers.
