# SHUT-090 Startup Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile persisted shard, repository, worktree, and container state at startup so Shuttle resumes safely after restart.

**Architecture:** Add a dedicated runtime reconciliation service that runs after repository bootstrap and database initialization inside `ShuttleServerApp.makeEnvironment`. The service will inspect persisted shard/runtime metadata, filesystem worktrees, git merge state, open conflict records, and Docker container state, then normalize repository and shard records while recording lifecycle events for degraded recoveries.

**Tech Stack:** Swift 6, SwiftPM, GRDB/SQLite, local git fixture repositories, fake Docker client abstractions.

---

## Implementation Notes

- `integrating` shard recovery uses persisted evidence in this order: identical branch tree to `shuttle-main` means `done`; an outstanding `shard_input_requested` event means `needs_input`; otherwise the shard returns to `running`.
- Repository blocked-state reconstruction prefers the oldest open blocking conflict ID and falls back to scanning linked git worktree metadata for `MERGE_HEAD`.
- Reconciliation outcomes are recorded as `shard_reconciled` audit events so degraded recovery is visible through the existing events API.

### Task 1: Capture restart expectations in tests

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleStartupReconciliationTests.swift`
- Read: `Sources/ShuttleServer/ShuttleServerApp.swift`
- Read: `Sources/ShuttleServer/Database/ShuttleShardStore.swift`
- Read: `Sources/ShuttleServer/Database/ShuttleConflictStore.swift`
- Read: `Sources/ShuttleServer/Docker/ShuttleShardContainerService.swift`

- [ ] **Step 1: Write failing startup reconciliation tests**

```swift
func testStartupReconciliationKeepsDoneShardWhenRetainedWorktreeIsMissing() async throws
func testStartupReconciliationRecreatesContainerForRunningShardWithExistingWorktree() async throws
func testStartupReconciliationMarksRunningShardFailedWhenWorktreeIsMissing() async throws
func testStartupReconciliationRebuildsBlockedRepositoryStateFromOpenConflict() async throws
func testStartupReconciliationNormalizesIntegratingShardToDoneWhenAlreadyMerged() async throws
```

Each test should:
- build a real fixture repository and SQLite database
- persist shard/runtime state before calling `ShuttleServerApp.makeEnvironment(...)`
- assert normalized shard state, repository state, and container metadata after startup
- assert lifecycle/audit evidence for degraded recovery paths

- [ ] **Step 2: Run only the new test file**

Run: `swift test --filter ShuttleStartupReconciliationTests`
Expected: FAIL with missing reconciliation behavior

### Task 2: Implement reconciliation service

**Files:**
- Create: `Sources/ShuttleServer/Runtime/ShuttleStartupReconciliationService.swift`
- Modify: `Sources/ShuttleServer/ShuttleServerApp.swift`
- Read: `Sources/ShuttleServer/Runtime/ShuttleConflictService.swift`
- Read: `Sources/ShuttleServer/Git/ShuttleWorktreeManager.swift`
- Read: `Sources/ShuttleServer/Docker/ShuttleShardContainerService.swift`

- [ ] **Step 1: Add reconciliation service skeleton**

Create a service that receives:
- `ShuttleConfig`
- `ShuttleRepositoryBootstrapResult`
- `ShuttleShardStore`
- `ShuttleRepositoryStateStore`
- `ShuttleConflictStore`
- `ShuttleAuditEventStore?`
- `ShuttleDockerAccessController`

Core entrypoint:

```swift
struct ShuttleStartupReconciliationService {
    func reconcile() async throws
}
```

- [ ] **Step 2: Implement repository-state reconstruction**

Rules:
- If open blocking conflicts exist, repository becomes `.blocked` with the oldest open blocking conflict ID.
- Else if `shuttle-main` has an active merge state, repository becomes `.blocked`.
- Else repository becomes `.open`.
- Always refresh stored `shuttleMainCommit`.

- [ ] **Step 3: Implement shard/worktree recovery**

Rules:
- `done` shard with missing retained worktree: keep `done`, keep metadata, record audit event.
- `running` or `needs_input` shard with missing worktree: move to `.failed`, record audit event.
- `running` shard with existing worktree: ensure container exists through `ShuttleShardContainerService.ensureContainer`.
- `needs_input` shard with existing worktree: leave state unchanged and do not force container recreation.

- [ ] **Step 4: Implement integrating-shard normalization**

Rules:
- If shard branch no longer exists and its changes are already reachable from `shuttle-main`, mark shard `.done`.
- If shard branch/worktree still exists and there is no active merge state, move shard back to `.running`.
- If repository is blocked, leave unresolved integrating shard `.failed` only when worktree is missing; otherwise prefer `.running` so an operator/agent can resume.
- Record an audit event for every integrating-state normalization.

- [ ] **Step 5: Wire reconciliation into startup**

In `ShuttleServerApp.makeEnvironment(...)`, after:
- config load
- database open
- repo bootstrap
- repository state bootstrap

call the reconciliation service before probing Docker health returns the environment.

- [ ] **Step 6: Re-run the reconciliation tests**

Run: `swift test --filter ShuttleStartupReconciliationTests`
Expected: PASS

### Task 3: Verification and commit

**Files:**
- Modify: `docs/superpowers/plans/2026-06-12-shut-090-startup-reconciliation.md`

- [ ] **Step 1: Run full verification**

Run: `swift test`
Expected: PASS

Run: `swift build`
Expected: PASS

- [ ] **Step 2: Update plan note with any implementation deltas**

Add a short verification section if the code path differs from the original plan.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/ShuttleServerApp.swift \
        Sources/ShuttleServer/Database/ShuttleAuditEventStore.swift \
        Sources/ShuttleServer/Runtime/ShuttleStartupReconciliationService.swift \
        Tests/ShuttleServerTests/ShuttleStartupReconciliationTests.swift \
        docs/superpowers/plans/2026-06-12-shut-090-startup-reconciliation.md
git commit -m "feat: add startup reconciliation"
```
