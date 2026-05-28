# SHUT-020 Database Migrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce SQLite migrations that create Shuttle v1 core tables for repository state, shards, conflicts, runtime metadata, completion reports, audit events, idempotency keys, and log indexes.

**Architecture:** Add a small database module (`ShuttleDatabase`) that owns `DatabaseQueue` creation and migration registration. Keep schema minimal but explicit so later tickets can build state machines and repositories without schema churn.

**Tech Stack:** Swift 6, GRDB, SQLite, XCTest

---

### Task 1: Add Migration Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleDatabaseMigrationsTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testMigrationsCreateExpectedTables() throws
func testMigrationsAllowReopenWithoutError() throws
func testShardIdentityIsSeparateFromBranchName() throws
func testLogIndexSchemaStoresReferencesNotRawLogContents() throws
```

- [ ] **Step 2: Run focused tests to verify red state**

Run: `swift test --filter ShuttleDatabaseMigrationsTests`
Expected: FAIL because `ShuttleDatabase` and migrations do not exist.

### Task 2: Implement Database Module And Initial Migration

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ShuttleServer/Database/ShuttleDatabase.swift`

- [ ] **Step 1: Add GRDB dependency**

```swift
.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
```

- [ ] **Step 2: Add migration runner and schema**

```swift
enum ShuttleDatabase {
    static func openMigrated(atPath path: String) throws -> DatabaseQueue
}
```

Tables:
- `repository_state`
- `shards`
- `conflicts`
- `shard_runtime_metadata`
- `completion_reports`
- `audit_events`
- `idempotency_keys`
- `log_indexes`

Constraints:
- Immutable shard identity in `shards.id`.
- Branch/worktree/container metadata in `shard_runtime_metadata`.
- Raw log references only in `log_indexes` (`file_path`, offsets), no log content column.

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-05-28-shut-020-database-migrations.md`

- [ ] **Step 1: Run focused migration tests**

Run: `swift test --filter ShuttleDatabaseMigrationsTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved Sources/ShuttleServer/Database/ShuttleDatabase.swift Tests/ShuttleServerTests/ShuttleDatabaseMigrationsTests.swift docs/superpowers/plans/2026-05-28-shut-020-database-migrations.md
git commit -m "feat: add Shuttle database migrations"
```

## Self-Review

- Spec coverage: migration tables and constraints match `SHUT-020` acceptance criteria.
- Placeholder scan: no TODO or deferred placeholders in migration code.
- Type consistency: schema names align with tests and intended downstream repository APIs.
