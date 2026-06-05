# SHUT-032 Create And Retain Worktrees Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create one deterministic worktree per shard from `shuttle-main`, persist the shard base commit and runtime metadata, and retain completed worktrees as read-only with a retention deadline.

**Architecture:** Add a small worktree manager under `Sources/ShuttleServer/Git`, a shard metadata store under `Sources/ShuttleServer/Database`, and a narrow orchestration service under `Sources/ShuttleServer/Runtime` that combines both. Keep container concerns out of scope; runtime metadata may use placeholder container fields until the Docker ticket lands.

**Tech Stack:** Swift 6, Foundation, GRDB, Git CLI, XCTest

---

### Task 1: Add Worktree Contract Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleWorktreeManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- shard creation records base commit and runtime metadata
- deterministic worktree path from shard ID and branch name
- duplicate shard creation is rejected
- retained done shard becomes read-only and stores `retainedUntil`

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleWorktreeManagerTests`
Expected: FAIL until store and worktree service exist.

### Task 2: Add Worktree And Shard Metadata Services

**Files:**
- Create: `Sources/ShuttleServer/Git/ShuttleWorktreeManager.swift`
- Create: `Sources/ShuttleServer/Database/ShuttleShardStore.swift`
- Create: `Sources/ShuttleServer/Runtime/ShuttleShardWorkspaceService.swift`

- [ ] **Step 1: Implement deterministic worktree creation**

Rules:
- branch starts from current `shuttle-main`
- worktree path is deterministic from shard ID and branch name
- duplicate refs or existing worktree paths are rejected

- [ ] **Step 2: Persist shard and runtime metadata**

Rules:
- `shards.base_commit` recorded at creation
- `shard_runtime_metadata` records branch and worktree path
- placeholder container metadata is explicit and deterministic

- [ ] **Step 3: Implement read-only retention**

Rules:
- `retainDoneShard` marks all worktree files non-writable
- `shards.state` becomes `done`
- `shards.retained_until` is set

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-06-05-shut-032-create-and-retain-worktrees.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleWorktreeManagerTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/Git/ShuttleWorktreeManager.swift Sources/ShuttleServer/Database/ShuttleShardStore.swift Sources/ShuttleServer/Runtime/ShuttleShardWorkspaceService.swift Tests/ShuttleServerTests/ShuttleWorktreeManagerTests.swift docs/superpowers/plans/2026-06-05-shut-032-create-and-retain-worktrees.md
git commit -m "feat: create and retain Shuttle worktrees"
```

## Self-Review

- Spec coverage: base commit persistence, deterministic worktree paths, duplicate prevention, and retained read-only worktrees are all encoded directly in tests.
- Placeholder scan: no TODO placeholders.
- Boundary discipline: bare repo bootstrap remains separate; this ticket only adds shard-level worktree behavior on top of it.
