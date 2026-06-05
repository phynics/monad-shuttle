# SHUT-041 Manage Per-Shard Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each shard a long-lived container mounted to its worktree, persist container metadata in SQLite, and recreate the container on restart when the stored container is missing.

**Architecture:** Extend the Docker client abstraction with create, inspect, and stop operations. Add a shard container service that consumes shard runtime metadata plus config to manage one deterministic container per shard. Keep command execution out of scope.

**Tech Stack:** Swift 6, Foundation, GRDB, XCTest

---

### Task 1: Add Container Lifecycle Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleShardContainerServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- container create uses configured image and worktree mount
- inspect returns current Docker state
- stop updates persisted metadata
- ensure/recreate restores missing container from stored metadata

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleShardContainerServiceTests`
Expected: FAIL until Docker client and container service exist.

### Task 2: Implement Per-Shard Container Management

**Files:**
- Update: `Sources/ShuttleServer/Docker/ShuttleDockerClient.swift`
- Update: `Sources/ShuttleServer/Database/ShuttleShardStore.swift`
- Create: `Sources/ShuttleServer/Docker/ShuttleShardContainerService.swift`

- [ ] **Step 1: Extend Docker client abstraction**

Rules:
- create, inspect, and stop are fakeable
- request model captures name, image, mounts, and working directory

- [ ] **Step 2: Persist container metadata**

Rules:
- container name is deterministic from shard ID
- SQLite runtime metadata stores container name and status
- recreate uses stored metadata and config, not ad hoc values

- [ ] **Step 3: Add restart-safe ensure flow**

Rules:
- if stored container is missing, recreate it with the same name
- if it exists, inspect and sync status
- if Docker is unavailable, guarded access still fails with structured errors from `SHUT-040`

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-06-05-shut-041-manage-per-shard-containers.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleShardContainerServiceTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/Docker/ShuttleDockerClient.swift Sources/ShuttleServer/Database/ShuttleShardStore.swift Sources/ShuttleServer/Docker/ShuttleShardContainerService.swift Tests/ShuttleServerTests/ShuttleShardContainerServiceTests.swift docs/superpowers/plans/2026-06-05-shut-041-manage-per-shard-containers.md
git commit -m "feat: manage Shuttle shard containers"
```

## Self-Review

- Spec coverage: create, inspect, stop, metadata persistence, and restart recreate are all covered directly in tests.
- Placeholder scan: no TODO placeholders.
- Scope control: this ticket stops at container lifecycle; `docker exec` command execution stays in `SHUT-042`.
