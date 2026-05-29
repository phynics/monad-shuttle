# SHUT-022 Audit And Lifecycle Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record important shard/conflict/push lifecycle actions as append-only audit events with actor identity and structured payloads.

**Architecture:** Add a GRDB-backed `ShuttleAuditEventStore` that appends to `audit_events` and exposes read APIs for later paging endpoints. Enforce append-only behavior at the database level with triggers that block `UPDATE` and `DELETE`.

**Tech Stack:** Swift 6, GRDB, SQLite, XCTest

---

### Task 1: Add Audit Event Store Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleAuditEventStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- records shard creation, finish request, input answer, abandon
- records conflict creation and resolution
- records push audit action
- stores actor identity and required event metadata
- rejects update/delete attempts on `audit_events`

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleAuditEventStoreTests`
Expected: FAIL until store and append-only enforcement are implemented.

### Task 2: Implement Append-Only Audit Event Store

**Files:**
- Modify: `Sources/ShuttleServer/Database/ShuttleDatabase.swift`
- Create: `Sources/ShuttleServer/Database/ShuttleAuditEventStore.swift`

- [ ] **Step 1: Enforce append-only at DB layer**

Add SQL triggers:
- `audit_events_prevent_update`
- `audit_events_prevent_delete`

- [ ] **Step 2: Add typed audit event store**

Types:
- `ShuttleActorIdentity`
- `ShuttleAuditEvent`
- `ShuttleAuditEventStore`

Store methods:
- `recordShardCreated`
- `recordShardFinishRequested`
- `recordShardInputAnswered`
- `recordShardAbandoned`
- `recordConflictCreated`
- `recordConflictResolved`
- `recordPushAction`
- `fetchAll`

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-05-29-shut-022-audit-lifecycle-events.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleAuditEventStoreTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/Database/ShuttleDatabase.swift Sources/ShuttleServer/Database/ShuttleAuditEventStore.swift Tests/ShuttleServerTests/ShuttleAuditEventStoreTests.swift docs/superpowers/plans/2026-05-29-shut-022-audit-lifecycle-events.md
git commit -m "feat: add Shuttle audit lifecycle event store"
```

## Self-Review

- Spec coverage: records required lifecycle event categories with actor metadata and structured payload.
- Placeholder scan: no TODO placeholders.
- Type consistency: event types and entity IDs are stable string contracts for upcoming API endpoints.
